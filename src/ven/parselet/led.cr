module Ven
  private module Parselet
    abstract struct Led
      getter precedence : Int32

      def initialize(
        @precedence)
      end

      abstract def parse(
        p : Parser,
        tag : NodeTag,
        left : Node,
        token : Token)
    end

    struct Binary < Led
      def parse(p, tag, left, token)
        QBinary.new(tag, token[:type].downcase, left, p.infix(@precedence))
      end
    end

    struct Call < Led
      def parse(p, tag, left, token)
        QCall.new(tag, left, p.repeat(")", ","))
      end
    end

    struct Assign < Led
      def parse(p, tag, left, token)
        !left.is_a?(QSymbol) \
          ? p.die("left-hand side of '=' is not a symbol")
          : QAssign.new(tag, left.value, p.infix)
      end
    end

    struct IntoBool < Led
      def parse(p, tag, left, token)
        QIntoBool.new(tag, left)
      end
    end

    struct RetInc < Led
      def parse(p, tag, left, token)
        !left.is_a?(QSymbol) \
          ? p.die("postfix '++' is an assignment, so symbol must be given")
          : QReturnIncrement.new(tag, left.value)
      end
    end

    struct RetDec < Led
      def parse(p, tag, left, token)
        !left.is_a?(QSymbol) \
          ? p.die("postfix '--' is an assignment, so symbol must be given")
          : QReturnDecrement.new(tag, left.value)
      end
    end
  end
end
