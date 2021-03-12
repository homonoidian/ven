module Ven
  module Parselet
    include Suite

    # Left-denotated token parser works with a *token*, to the
    # *left* of which there is a quote of interest.
    abstract class Led
      getter precedence : UInt8

      def initialize(@precedence)
      end

      # Performs the parsing.
      abstract def parse(
        parser : Reader,
        tag : QTag,
        left : Quote,
        token : Token)
    end

    # Parses a binary operation into a QBinary: `2 + 2`,
    # `2 is "2"`, `1 ~ 2` etc.
    class PBinary < Led
      # These operators may be followed by a `not`:
      NOT_FOLLOWS = %(IS)

      def parse(parser, tag, left, token)
        not = NOT_FOLLOWS.includes?(token[:type]) && parser.word!("NOT")
        this = QBinary.new(tag, token[:lexeme], left, parser.led(@precedence))

        not ? QUnary.new(tag, "not", this) : this
      end
    end

    # Parses a call into a QCall: `x(1)`, `[1, 2, 3](1, 2)`,
    # etc.
    class PCall < Led
      def parse(parser, tag, left, token)
        QCall.new(tag, left, parser.repeat(")", ","))
      end
    end

    # Parses an assignment expression into a QAssign:
    # `foo := "bar"`, `foo = 123.456`, etc.
    class PAssign < Led
      def parse(parser, tag, left, token)
        kind = token[:type]

        !left.is_a?(QSymbol) \
          ? parser.die("left-hand side of '#{kind}' must be a symbol")
          : QAssign.new(tag, left.value, parser.led, kind == ":=")
      end
    end

    # Parses a binary operator assignment into a QBinaryAssign:
    # `x += 2`, `foo ~= 3`, etc.
    class PBinaryAssign < Led
      def parse(parser, tag, left, token)
        operator = token[:type].chars.first.to_s

        unless left.is_a?(QSymbol)
          parser.die("left-hand side of '#{token[:type]}' must be a symbol")
        end

        QBinaryAssign.new(tag, operator, left.value, parser.led)
      end
    end

    # Parses an into-bool expression into a QIntoBool: `x is 4?`,
    # `[1, 2, false]?`, etc.
    class PIntoBool < Led
      def parse(parser, tag, left, token)
        QIntoBool.new(tag, left)
      end
    end

    # Parses a return-increment expression into a QReturnIncrement:
    # `x++`, `foo_bar++`, etc.
    class PReturnIncrement < Led
      def parse(parser, tag, left, token)
        !left.is_a?(QSymbol) \
          ? parser.die("postfix '++' expects a symbol")
          : QReturnIncrement.new(tag, left.value)
      end
    end

    # Parses a return-decrement expression into a QReturnDecrement:
    # `x--`, `foo_bar--`, etc.
    class PReturnDecrement < Led
      def parse(parser, tag, left, token)
        !left.is_a?(QSymbol) \
          ? parser.die("postfix '--' expects a symbol")
          : QReturnDecrement.new(tag, left.value)
      end
    end

    # Parses a field access expression into a QAccessField:
    # `a.b.c`, `1.bar`, `"quux".strip!`, etc. Also parses
    # multifield access (`a.[b, c]`) and dynamic field
    # access (`a.(b)`).
    class PAccessField < Led
      def parse(parser, tag, left, token)
        path = parser.repeat(sep: ".", unit: -> { member(parser, tag) })

        QAccessField.new(tag, left, path)
      end

      def member(parser, tag)
        token = parser.expect("SYMBOL", "[", "(")

        if token[:type] == "SYMBOL"
          SingleFieldAccessor.new(token[:lexeme])
        elsif token[:type] == "("
          DynamicFieldAccessor.new(PGroup.new.parse(parser, tag, token))
        else # if it[:type] == "["
          vector = PVector.new.parse(parser, tag, token)

          # Wrap all vector items into dynamic field accessors:
          wrapped =
            vector.items.map do |route|
              DynamicFieldAccessor.new(route)
            end

          MultiFieldAccessor.new(wrapped)
        end
      end
    end
  end
end
