module Ven
  private module Parselet
    include Component

    abstract struct Nud
      # Parses a block (requiring initial '{' if *initial* is true).
      def block(parser, initial = true)
        if initial
          parser.expect("{")
        end

        statement = -> do
          parser.statement("}", detrail: false)
        end

        parser.repeat("}", unit: statement)
      end

      # Ensures that what the given *block* parses is followed
      # by a semicolon (or EOF).
      def semicolon(parser, &)
        result = yield

        parser.expect(";", "EOF")

        result
      end

      abstract def parse(
        parser : Parser,
        tag : NodeTag,
        token : Token)
    end

    struct Unary < Nud
      def initialize(
        @precedence : Int32)
      end

      def parse(parser, tag, token)
        operand = parser.led(@precedence)

        QUnary.new(tag, token[:type].downcase, operand)
      end
    end

    struct Symbol < Nud
      def parse(parser, tag, token)
        QSymbol.new(tag, token[:raw])
      end
    end

    struct String < Nud
      def parse(parser, tag, token)
        QString.new(tag, token[:raw][1...-1])
      end
    end

    struct Regex < Nud
      def parse(parser, tag, token)
        QRegex.new(tag, token[:raw][1...-1])
      end
    end

    struct Number < Nud
      def parse(parser, tag, token)
        QNumber.new(tag, token[:raw])
      end
    end

    struct UPop < Nud
      def parse(parser, tag, token)
        QUPop.new(tag)
      end
    end

    struct URef < Nud
      def parse(parser, tag, token)
        QURef.new(tag)
      end
    end

    struct Group < Nud
      def parse(parser, tag, token)
        parser.before(")")
      end
    end

    struct Vector < Nud
      def parse(parser, tag, token)
        items = parser.repeat("]", ",")

        QVector.new(tag, items)
      end
    end

    struct Spread < Nud
      def parse(parser, tag, token)
        lambda = nil
        iterative = false

        parser.led?(only: Binary).keys.each do |operator|
          # XXX: is handling 'is not' so necessary?

          if consumed = parser.word(operator)
            if parser.word("|")
              return QBinarySpread.new(tag, operator.downcase, parser.led)
            end

            # Gather the unaries:
            unaries = parser.nud?(only: Unary)

            # Make sure the operator is actually unary:
            unless unaries.has_key?(operator)
              parser.die("expected '|' or a term")
            end

            # Here we know we've consumed a unary by accident.
            # Let the unary parser do the job
            break lambda = unaries[operator]
              .parse(parser, QTag.new(tag.file, consumed[:line]), consumed)
          end
        end

        lambda ||= parser.led

        parser.expect("|")

        # Is it an iterative spread?
        if parser.word(":")
          iterative = true
        end

        QLambdaSpread.new(tag, lambda, parser.led, iterative)
      end
    end

    struct Block < Nud
      def parse(parser, tag, token)
        statements = block(parser, initial: false)

        QBlock.new(tag, statements)
      end
    end

    struct If < Nud
      def parse(parser, tag, tok)
        cond = parser.led
        succ = parser.led
        fail = parser.word("ELSE") ? parser.led : nil

        QIf.new(tag, cond, succ, fail)
      end
    end

    struct Fun < Nud
      def parse(parser, tag, token)
        name = parser.expect("SYMBOL")[:raw]

        # Parse the parameters and slurpiness.
        params, slurpy = [] of ::String, false

        if parser.word("(")
          slurpy = false

          parameter = -> do
            if parser.word("*")
              unless slurpy = !slurpy
                parser.die("having several '*' in function parameters is forbidden")
              end
            else
              parser.expect("SYMBOL")[:raw]
            end
          end

          params = parser
            .repeat(")", ",", unit: parameter)
            .compact
        end

        # Parse the given appendix.
        given = [] of Quote

        if parser.word("GIVEN")
          parser.repeat(sep: ",", unit: -> { parser.led(Precedence::ASSIGNMENT.value) })
        end

        # Parse the body.
        body = parser.word("=") \
          ? semicolon(parser) { [parser.led] }
          : block(parser)

        if params.empty? && !given.empty?
          parser.die("could not use 'given' for a zero-arity function")
        end

        QFun.new(tag, name, params, body, given, slurpy)
      end
    end

    struct Queue < Nud
      def parse(parser, tag, token)
        QQueue.new(tag, parser.led)
      end
    end

    struct Ensure < Nud
      def parse(parser, tag, token)
        QEnsure.new(tag, parser.led)
      end
    end

    struct While < Nud
      def parse(parser, tag, token)
        condition = parser.led
        block = parser.led

        QWhile.new(tag, condition, block)
      end
    end

    struct Until < Nud
      def parse(parser, tag, token)
        condition = parser.led
        block = parser.led

        QUntil.new(tag, condition, block)
      end
    end
  end
end
