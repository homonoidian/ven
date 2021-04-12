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
        QAssign.new(tag,
          PAssign
            .validate(parser, left)
            .value,
          parser.led,
          token[:type] == ":=")
      end

      # Returns whether *left* is a valid assignment target.
      def self.validate?(left : Quote) : Bool
        left.is_a?(QSymbol) && left.value != "*"
      end

      # Returns *left* if it is a valid assignment target.
      # Otherwise, dies of read error.
      def self.validate(parser, left : Quote)
        unless self.validate?(left)
          parser.die("illegal assignment target")
        end

        left.as(QSymbol)
      end
    end

    # Parses a binary operator assignment into a QBinaryAssign:
    # `x += 2`, `foo ~= 3`, etc.
    class PBinaryAssign < Led
      def parse(parser, tag, left, token)
        QBinaryAssign.new(tag,
          token[:type][0].to_s,
          PAssign
            .validate(parser, left)
            .value,
          parser.led)
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
    # dynamic field access (`a.(b)`) and branches field access
    # (`a.[b.c, d]`).
    class PAccessField < Led
      def parse(parser, tag, left, token)
        QAccessField.new(tag, left, pieces parser)
      end

      # Parses the pieces (those that are separated by dots)
      # of the path.
      def pieces(parser)
        parser.repeat(sep: ".", unit: -> { piece parser })
      end

      # Parses an individual piece. It may either be a branches
      # access piece, dynamic field access piece, or an immediate
      # field access piece.
      def piece(parser)
        lead = parser.expect("[", "(", "SYMBOL")

        case lead[:type]
        when "["
          FABranches.new(branches parser)
        when "("
          FADynamic.new(dynamic parser)
        when "SYMBOL"
          FAImmediate.new(lead[:lexeme])
        end.not_nil!
      end

      # Parses a branches field access piece, which is,
      # essentially, a vector.
      def branches(parser)
        PVector.new.parse(parser, QTag.void, word?)
      end

      # Parses a dynamic field access piece, which is,
      # essentially, a grouping.
      def dynamic(parser)
        PGroup.new.parse(parser, QTag.void, word?)
      end

      # Returns a fictious word.
      private macro word?
        { type: ".", lexeme: ".", line: 0 }
      end
    end

    # Parses postfix 'dies' into a QDies: `1 dies`,
    # `die("hi") dies`, etc.
    class PDies < Led
      def parse(parser, tag, left, token)
        QDies.new(tag, left)
      end
    end
  end
end
