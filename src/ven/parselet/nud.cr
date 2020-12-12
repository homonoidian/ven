module Ven
  private module Parselet
    abstract struct Nud
      macro block
        p.expect("{"); p.repeat("}", unit: -> { p.statement("}", detrail: false) })
      end

      abstract def parse(
        p : Parser,
        tag : NodeTag,
        token : Token)
    end

    struct Unary < Nud
      def initialize(
        @precedence : Int32)
      end

      def parse(p, tag, token)
        QUnary.new(tag, token[:type].downcase, p.infix(@precedence))
      end
    end

    struct Symbol < Nud
      def parse(p, tag, token)
        QSymbol.new(tag, token[:raw])
      end
    end

    struct String < Nud
      def parse(p, tag, token)
        QString.new(tag, token[:raw][1...-1])
      end
    end

    struct Number < Nud
      def parse(p, tag, token)
        QNumber.new(tag, token[:raw])
      end
    end

    struct UPop < Nud
      def parse(p, tag, token)
        QUPop.new(tag)
      end
    end

    struct URef < Nud
      def parse(p, tag, token)
        QURef.new(tag)
      end
    end

    struct Group < Nud
      def parse(p, tag, token)
        p.before(")")
      end
    end

    struct Vector < Nud
      def parse(p, tag, token)
        QVector.new(tag, p.repeat("]", ",", ->p.infix))
      end
    end

    struct Spread < Nud
      def parse(p, tag, token)
        # Grab all binary operator token types (so keys)
        binaries = p.@led.reject { |_, v| !v.is_a?(Binary) }.keys
        if operator = binaries.find { |binary| p.consume(binary) }
          # If consumed a binary operator, it's a binary spread
          QBinarySpread.new(tag, operator.downcase, body!)
        else
          QLambdaSpread.new(tag, p.infix, body!)
        end
      end

      private macro body!
        p.expect("|"); p.infix
      end
    end

    struct Block < Nud
      def parse(p, tag, tok)
        QBlock.new(tag, p.repeat("}", unit: -> { p.statement("}", detrail: false) }))
      end
    end

    struct If < Nud
      def parse(p, tag, tok)
        QIf.new(tag, p.infix, p.infix, p.consume("ELSE") ? p.infix : nil)
      end
    end

    struct Fun < Nud
      def parse(p, tag, token)
        name = p.expect("SYMBOL")[:raw]
        # Params part
        params = p.consume("(") \
          ? p.repeat(")", ",", -> { p.expect("SYMBOL")[:raw] })
          : [] of ::String
        # Meaning part
        meanings = [] of Quote
        if p.consume("MEANING")
          meanings = params.empty? \
            ? p.die("'meaning' illegal when given no parameters")
            : p.repeat(sep: ",", unit: -> p.prefix)
        end
        # `= ...` or `{ ... }` part
        if p.consume("=")
          body = [p.infix]
          # `=` functions must end with a semicolon:
          p.expect(";", "EOF")
        else
          body = block
        end
        QFun.new(tag, name, params, body, meanings)
      end
    end
  end
end
