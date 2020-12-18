module Ven
  private module Parselet
    include Component

    abstract struct Nud
      # TODO: make this more flexible!
      macro block
        p.expect("{"); p.repeat("}", unit: -> { p.statement("}", detrail: false) })
      end

      macro semicolon(&block)
        result = {{yield}}
        p.expect(";", "EOF")
        result
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
        QVector.new(tag, p.repeat("]", ","))
      end
    end

    struct Spread < Nud
      def parse(p, tag, token)
        # Grab all binary operator token types
        binaries = p.@led.reject { |_, v| !v.is_a?(Binary) }.keys

        # If consumed a binary token type, it's a binary spread
        binaries.each do |binary|
          if p.consume(binary)
            return QBinarySpread.new(tag, binary.downcase, body!)
          end
        end

        QLambdaSpread.new(tag, p.infix, body!)
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

        params = p.consume("(") \
          ? p.repeat(")", ",", -> { p.expect("SYMBOL")[:raw] })
          : [] of ::String

        given = [] of Quote
        if p.consume("GIVEN")
          given = params.empty? \
            ? p.die("'given' illegal for zero-arity functions")
            # Infixes with precedence greater (!) than ASSIGNMENT
            : p.repeat(sep: ",", unit: -> { p.infix(Precedence::ASSIGNMENT.value) })
        end

        if p.consume("=")
          body = [p.infix]
          # `=` functions must end with a semicolon (or EOF)
          p.expect(";", "EOF")
        else
          body = block
        end

        QFun.new(tag, name, params, body, given)
      end
    end

    struct Ensure < Nud
      def parse(p, tag, token)
        QEnsure.new(tag, p.infix)
      end
    end
  end
end
