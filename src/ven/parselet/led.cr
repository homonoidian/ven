module Ven
  private module Parselet
    include Component

    abstract struct Led
      getter precedence : Int32

      def initialize(
        @precedence)
      end

      abstract def parse(
        parser : Parser,
        tag : NodeTag,
        left : Node,
        token : Token)
    end

    struct Binary < Led
      def parse(parser, tag, left, token)
        operator = token[:type].downcase

        # Is it 'is not'?
        inverse = parser.consume("NOT") if operator == "is"
        right = parser.infix(@precedence)
        this = QBinary.new(tag, operator, left, right)

        inverse.nil? ? this : QUnary.new(tag, "not", this)
      end
    end

    struct Call < Led
      def parse(parser, tag, left, token)
        args = parser.repeat(")", ",")

        QCall.new(tag, left, args)
      end
    end

    struct Assign < Led
      def parse(parser, tag, left, token)
        !left.is_a?(QSymbol) \
          ? parser.die("left-hand side of '=' is not a symbol")
          : QAssign.new(tag, left.value, parser.infix)
      end
    end

    struct IntoBool < Led
      def parse(parser, tag, left, token)
        QIntoBool.new(tag, left)
      end
    end

    struct ReturnIncrement < Led
      def parse(parser, tag, left, token)
        !left.is_a?(QSymbol) \
          ? parser.die("postfix '++' expects a symbol")
          : QReturnIncrement.new(tag, left.value)
      end
    end

    struct ReturnDecrement < Led
      def parse(parser, tag, left, token)
        !left.is_a?(QSymbol) \
          ? parser.die("postfix '--' expects a symbol")
          : QReturnDecrement.new(tag, left.value)
      end
    end

    struct AccessField < Led
      def parse(parser, tag, left, token)
        path = [] of ::String

        while token && token[:type] == "."
          path << parser.expect("SYMBOL")[:raw]
          token = parser.consume(".")
        end

        QAccessField.new(tag, left, path)
      end
    end
  end
end
