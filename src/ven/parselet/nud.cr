module Ven
  module Parselet
    include Component

    # Null-denotated token parser works with tokens that are
    # not preceded by a meaningful (important to this parser)
    # token.
    abstract class Nud
      # Parses a block (requiring opening '{' if *opening* is true).
      private macro block(parser, opening = true)
        begin
          {% if opening %}
            {{parser}}.expect("{")
          {% end %}

          {{parser}}.repeat("}", unit: -> {
            {{parser}}.statement("}", detrail: false)
          })
        end
      end

      # Ensures that what the given *block* parses is followed
      # by a semicolon (or EOF).
      private macro semicolon(parser, &)
        (result = begin {{yield}} end; {{parser}}.expect(";", "EOF"); result)
      end

      # Perform the parsing.
      abstract def parse(
        parser : Reader,
        tag : QTag,
        token : Token)
    end

    # Atoms are self-evaluating semantic constructs. *name*
    # is the name of the Nud class that will be generated;
    # *quote* is the quote that this Nud yields; *value*
    # determines whether to give the lexeme of the nud token
    # to the *quote* as an argument; and *unroll* is the
    # number of characters to remove from the beginning
    # and the end of the nud token's lexeme.
    private macro defatom(name, quote, value = true, unroll = 0)
      class {{name.id}} < Nud
        def parse(parser, tag, token)
          {{quote}}.new(tag,
            {% if value && unroll != 0 %}
              token[:lexeme][{{unroll}}...-{{unroll}}]
            {% elsif value %}
              token[:lexeme]
            {% end %})
        end
      end
    end

    # Parse a symbol into a QSymbol: `quux`, `foo-bar_baz-123`.
    defatom(PSymbol, QSymbol)

    # Parse a number into a QNumber: 1.23, 1234, 1_000.
    class PNumber < Nud
      def parse(parser, tag, token)
        parser.die("trailing '_' in number") if token[:lexeme].ends_with?("_")

        QNumber.new(tag, token[:lexeme].delete('_'))
      end
    end

    # Parse a string into a QString: `"foo bar baz\n"`.
    class PString < Nud
      # A hash of escaped escape sequences and what they should
      # evaluate to.
      SEQUENCES = {
        "\\n" => "\n",
        "\\t" => "\t",
        "\\r" => "\r",
        "\\\"" => "\"",
        "\\\\" => "\\"
      }

      # Evaluates the escape sequences in the *operand* String.
      def unescape(operand : String)
        SEQUENCES.each do |escape, raw|
          operand = operand.gsub(escape, raw)
        end

        operand
      end


      def parse(parser, tag, token)
        value = unescape(token[:lexeme][1...-1])

        QString.new(tag, value)
      end
    end

    # Parse a regex into a QRegex.
    defatom(PRegex, QRegex, unroll: 1)

    # Parse a underscores reference into a QURef: `&_`.
    defatom(PURef, QURef, value: false)

    # Parse a underscores pop into a QUPop: `_`.
    defatom(PUPop, QUPop, value: false)

    # Parse a unary operation into a QUnary. Examples of unary
    # operations are: `+12.34`, `~[1, 2, 3]`, `-true`, etc.
    class PUnary < Nud
      def initialize(
        @precedence : UInt8)
      end

      def parse(parser, tag, token)
        QUnary.new(tag,
          token[:type].downcase,
          parser.led(@precedence))
      end
    end

    # Parse a grouping, as example, `(2 + 2)`.
    class PGroup < Nud
      def parse(parser, tag, token)
        parser.before(")")
      end
    end

    # Parse a vector into a QVector, e.g., `[]`, `[1]`, `[4, 5, 6,]`.
    class PVector < Nud
      def parse(parser, tag, token)
        QVector.new(tag, parser.repeat("]", ","))
      end
    end

    # Parse a spread, e.g.: `|+| [1, 2, 3]` (reduce spread),
    # `|_ is 5| [1, 2, 3]` (map spread), `|say(_)|: [1, 2, 3]`
    # (iterative spread) into a QSpread.
    class PSpread < Nud
      def parse(parser, tag, token)
        lambda = nil
        iterative = false

        parser.led?(only: PBinary).keys.each do |operator|
          # XXX: is handling 'is not' so necessary?

          if consumed = parser.word(operator)
            if parser.word("|")
              return QBinarySpread.new(tag, operator.downcase, parser.led)
            end

            # Gather the unaries:
            unaries = parser.nud?(only: PUnary)

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

    # Parse a block into a QBlock, e.g., `{ 5 + 5; x = say(3); x }`.
    class PBlock < Nud
      def parse(parser, tag, token)
        QBlock.new(tag, block(parser, opening: false))
      end
    end

    # Parse an 'if' expression into a QIf, as example, `if true say("Yay!")`,
    # `if false say("Nay!") else say("Boo!")`.
    class PIf < Nud
      def parse(parser, tag, tok)
        cond = parser.led
        succ = parser.led
        fail = parser.word("ELSE") ? parser.led : nil

        QIf.new(tag, cond, succ, fail)
      end
    end

    # Parse a 'fun' statement into a QFun.
    class PFun < Nud
      def parse(parser, tag, token)
        name = parser.expect("SYMBOL")[:lexeme]

        # Parse the parameters and slurpiness.
        params, slurpy = [] of String, false

        if parser.word("(")
          slurpy = false

          parameter = -> do
            if parser.word("*")
              unless slurpy = !slurpy
                parser.die("having several '*' in function parameters is forbidden")
              end
            else
              parser.expect("SYMBOL")[:lexeme]
            end
          end

          params = parser
            .repeat(")", ",", unit: parameter)
            .compact
        end

        # Parse the given appendix.
        given = [] of Quote

        if parser.word("GIVEN")
          given = parser.repeat(sep: ",", unit: -> { parser.led(Precedence::ASSIGNMENT.value) })
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

    # Parse a 'queue' expression into a QQueue: `queue 1 + 2`.
    class PQueue < Nud
      def parse(parser, tag, token)
        QQueue.new(tag, parser.led)
      end
    end

    # Parse an 'ensure' expression into a QEnsure: `ensure 2 + 2 is 4`.
    class PEnsure < Nud
      def parse(parser, tag, token)
        QEnsure.new(tag, parser.led)
      end
    end

    # Parse a 'while' statement into a QWhile.
    class PWhile < Nud
      def parse(parser, tag, token)
        condition = parser.led

        # Receive a block. It can be either a QBlock or anything
        # else. If it is this anything else, expect a semicolon.
        block = parser.led

        parser.expect(";") unless block.is_a?(QBlock)

        QWhile.new(tag, condition, block)
      end
    end

    # Parse an 'until' statement into a QUntil.
    class PUntil < Nud
      def parse(parser, tag, token)
        condition = parser.led
        block = parser.led

        QUntil.new(tag, condition, block)
      end
    end
  end
end
