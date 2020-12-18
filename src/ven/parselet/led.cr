module Ven
  private module Parselet
    include Component

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
        args = p.repeat(")", ",")

        if left.is_a?(QAccessField)
          # If calling QAccessField, rearrange so to provide
          # UFCS-like behavior. XXX but calling fields?
          call = left.head

          left.path[...-1].each do |unit|
            call = QCall.new(tag, QSymbol.new(tag, unit), [call])
          end

          return QCall.new(tag, QSymbol.new(tag, left.path.last), [call] + args)
        end

        QCall.new(tag, left, args)
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

    struct ReturnIncrement < Led
      def parse(p, tag, left, token)
        !left.is_a?(QSymbol) \
          ? p.die("postfix '++' is an assignment, so symbol must be given")
          : QReturnIncrement.new(tag, left.value)
      end
    end

    struct ReturnDecrement < Led
      def parse(p, tag, left, token)
        !left.is_a?(QSymbol) \
          ? p.die("postfix '--' is an assignment, so symbol must be given")
          : QReturnDecrement.new(tag, left.value)
      end
    end

    struct AccessField < Led
      def parse(p, tag, left, token)
        path = [] of ::String

        while token && token[:type] == "."
          path << p.expect("SYMBOL")[:raw]
          token = p.consume(".")
        end

        QAccessField.new(tag, left, path)
      end
    end
  end
end
