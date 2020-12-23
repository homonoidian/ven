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
        operand = parser.infix(@precedence)

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

        parser.led(only: Binary).keys.each do |operator|
          # XXX: is handling 'is not' so necessary?

          if consumed = parser.consume(operator)
            if parser.consume("|")
              return QBinarySpread.new(tag, operator.downcase, parser.infix)
            end

            # Gather the unaries:
            unaries = parser.nud(only: Unary)

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

        lambda ||= parser.infix

        parser.expect("|")

        # Is it an iterative spread?
        if parser.consume(":")
          iterative = true
        end

        QLambdaSpread.new(tag, lambda, parser.infix, iterative)
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
        cond = parser.infix
        succ = parser.infix
        fail = parser.consume("ELSE") ? parser.infix : nil

        QIf.new(tag, cond, succ, fail)
      end
    end

    struct Fun < Nud
      def parse(parser, tag, token)
        name = parser.expect("SYMBOL")[:raw]
        params, slurpy = parameters(parser)
        given = given(parser)
        body = body(parser)

        if params.empty? && !given.empty?
          parser.die("could not use 'given' for a zero-arity function")
        end

        QFun.new(tag, name, params, body, given, slurpy)
      end

      # Parses this function's parameters. Returns a Tuple
      # that consists of (an Array of parameters) and slurpiness
      # (i.e., whether or not this function is slurpy).
      private def parameters(parser) : {Array(::String), Bool}
        return {[] of ::String, false} unless parser.consume("(")

        slurpy = false

        parameter = -> do
          if parser.consume("*")
            unless slurpy = !slurpy
              parser.die("having several '*' in function parameters is forbidden")
            end
          else
            parser.expect("SYMBOL")[:raw]
          end
        end

        {parser.repeat(")", ",", unit: parameter).compact, slurpy}
      end

      # Parses this function's 'given' appendix.
      private def given(parser) : Array(Quote)
        return [] of Quote unless parser.consume("GIVEN")

        type = -> do
          parser.infix(Precedence::ASSIGNMENT.value)
        end

        parser.repeat(sep: ",", unit: type)
      end

      # Parses this function's body.
      private def body(parser) : Array(Quote)
        if parser.consume("=")
          semicolon(parser) { [parser.infix] }
        else
          block(parser)
        end
      end
    end

    struct Ensure < Nud
      def parse(parser, tag, token)
        QEnsure.new(tag, parser.infix)
      end
    end
  end
end
