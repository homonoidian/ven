module Ven
  module Parselet
    include Component

    # Left-denotated token parser works with a *token*, to the
    # *left* of which a semantically meaningful construct exists.
    abstract class Led
      getter precedence : UInt8

      def initialize(
        @precedence)
      end

      # Perform the parsing.
      abstract def parse(
        parser : Reader,
        tag : QTag,
        left : Quote,
        token : Token)
    end

    # Parse a binary operation into a QBinary; `2 + 2`, `2 is "2"`,
    # `1 ~ 2` are all examples of a binary operation.
    class PBinary < Led
      def parse(parser, tag, left, token)
        not_ = token[:lexeme] == "is" && parser.word("NOT")
        this = QBinary.new(tag, token[:lexeme], left, parser.led(@precedence - 1))

        not_ ? QUnary.new(tag, "not", this) : this
      end
    end

    # Parse a call into a QCall: `x(1)`, `[1, 2, 3](1, 2)`,
    # for example.
    class PCall < Led
      def parse(parser, tag, left, token)
        QCall.new(tag, left, parser.repeat(")", ","))
      end
    end

    # Parse an assignment into a QAssign; `x = 2` is an example
    # of an assignment.
    class PAssign < Led
      def parse(parser, tag, left, token)
        !left.is_a?(QSymbol) \
          ? parser.die("left-hand side of '=' must be a symbol")
          : QAssign.new(tag, left.value, parser.led)
      end
    end

    # Parse a binary operator assignment into a QBinaryAssign.
    # E.g., `x += 2`, `foo ~= 3`.
    class PBinaryAssign < Led
      def parse(parser, tag, left, token)
        unless left.is_a?(QSymbol)
          parser.die("left-hand side of '#{token[:type]}' must be a symbol")
        end

        QBinaryAssign.new(tag,
          token[:type][0].to_s,
          left.value,
          parser.led)
      end
    end

    # Parse an into-bool expression into a QIntoBool. For example,
    # `x is 4?`.
    class PIntoBool < Led
      def parse(parser, tag, left, token)
        QIntoBool.new(tag, left)
      end
    end

    # Parse a return-increment expression into a QReturnIncrement.
    # E.g., `x++`, `foo_bar++`.
    class PReturnIncrement < Led
      def parse(parser, tag, left, token)
        !left.is_a?(QSymbol) \
          ? parser.die("postfix '++' expects a symbol")
          : QReturnIncrement.new(tag, left.value)
      end
    end

    # Parse a return-decrement expression into a QReturnDecrement.
    # E.g., `x--`, `foo_bar--`.
    class PReturnDecrement < Led
      def parse(parser, tag, left, token)
        !left.is_a?(QSymbol) \
          ? parser.die("postfix '--' expects a symbol")
          : QReturnDecrement.new(tag, left.value)
      end
    end

    # Parse a field access expression into a QAccessField.
    # `a.b.c`, `1.bar`, `"quux".strip!` are all examples
    # of a field access expression.
    class PAccessField < Led
      def parse(parser, tag, left, token)
        path = [] of String

        while token && token[:type] == "."
          path << parser.expect("SYMBOL")[:lexeme]
          token = parser.word(".")
        end

        QAccessField.new(tag, left, path)
      end
    end
  end
end
