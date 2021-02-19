module Ven
  module Parselet
    include Component

    # Null-denotated token parser works with tokens that are
    # not preceded by a meaningful (important to this parser)
    # token.
    abstract class Nud
      @semicolon = true

      # Parses a block (requiring opening '{' if *opening* is true).
      private macro block(parser, opening = true)
        begin
          @semicolon = false

          {% if opening %}
            {{parser}}.expect("{")
          {% end %}

          {{parser}}.repeat("}", unit: ->{{parser}}.statement)
        end
      end

      # Returns whether this Nud requires a semicolon.
      def semicolon?
        @semicolon
      end

      # Performs the parsing.
      abstract def parse(
        parser : Reader,
        tag : QTag,
        token : Token)
    end

    # Atoms are self-evaluating semantic constructs. *name*
    # is the name of the Nud class that will be generated;
    # *quote* is the quote this Nud produces; *argument*
    # determines whether to give the lexeme of the nud token
    # to the *quote* as an argument; *unroll* is the number
    # of characters to remove from the beginning and the end
    # of the nud token's lexeme.
    private macro defatom(name, quote, argument = true, unroll = 0)
      class {{name.id}} < Nud
        def parse(parser, tag, token)
          {{quote}}.new(tag,
            {% if argument && unroll != 0 %}
              token[:lexeme][{{unroll}}...-{{unroll}}]
            {% elsif argument %}
              token[:lexeme]
            {% end %})
        end
      end
    end

    # Parses a symbol into a QSymbol: `quux`, `foo-bar_baz-123`.
    defatom(PSymbol, QSymbol)

    # Parses a number into a QNumber: 1.23, 1234, 1_000.
    class PNumber < Nud
      def parse(parser, tag, token)
        parser.die("trailing '_' in number") if token[:lexeme].ends_with?("_")

        QNumber.new(tag, token[:lexeme].delete('_'))
      end
    end

    # Parses a string into a QString: `"foo bar baz\n"`.
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

    # Parses a regex into a QRegex.
    defatom(PRegex, QRegex, unroll: 1)

    # Parses a underscores reference into a QURef: `&_`.
    defatom(PURef, QURef, argument: false)

    # Parses a underscores pop into a QUPop: `_`.
    defatom(PUPop, QUPop, argument: false)

    # Parses a unary operation into a QUnary. Examples of unary
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

    # Parses a grouping, as example, `(2 + 2)`.
    class PGroup < Nud
      def parse(parser, tag, token)
        parser.before(")")
      end
    end

    # Parses a vector into a QVector, e.g., `[]`, `[1]`, `[4, 5, 6,]`.
    class PVector < Nud
      def parse(parser, tag, token)
        QVector.new(tag, parser.repeat("]", ","))
      end
    end

    # Parses a spread, e.g.: `|+| [1, 2, 3]` (reduce spread),
    # `|_ is 5| [1, 2, 3]` (map spread), `|say(_)|: [1, 2, 3]`
    # (iterative spread) into a QSpread.
    class PSpread < Nud
      def parse(parser, tag, token)
        lambda = nil
        iterative = false

        parser.led?(only: PBinary).keys.each do |operator|
          if consumed = parser.word!(operator)
            if parser.word!("|")
              return QBinarySpread.new(tag, operator.downcase, parser.led)
            end

            # As there is no backtracking, we have to manually
            # check if this is a unary (e.g., `|+<--HERE-->_| [1, 2, 3]`).
            unaries = parser.nud?(only: PUnary)

            # Make sure the operator is really a unary:
            unless unaries.has_key?(operator)
              parser.die("expected '|' or a term")
            end

            # We've accidentally consumed a unary. Let the unary
            # parser do the job instead, and consider this spread
            # a lambda spread from now on.
            break lambda = unaries[operator]
              .parse(parser, QTag.new(tag.file, consumed[:line]), consumed)
          end
        end

        lambda ||= parser.led

        parser.expect("|")

        # Is this spread an iterative spread?
        iterative = true if parser.word!(":")

        QLambdaSpread.new(tag, lambda, parser.led, iterative)
      end
    end

    # Parses a block into a QBlock, e.g., `{ 5 + 5; x = say(3); x }`.
    class PBlock < Nud
      def parse(parser, tag, token)
        QBlock.new(tag, block(parser, opening: false))
      end
    end

    # Parses an 'if' expression into a QIf, as example, `if true say("Yay!")`,
    # `if false say("Nay!") else say("Boo!")`.
    class PIf < Nud
      def parse(parser, tag, tok)
        cond = parser.led
        succ = parser.led
        fail = parser.word!("ELSE") ? parser.led : nil

        QIf.new(tag, cond, succ, fail)
      end
    end

    # Parses a 'fun' statement into a QFun.
    class PFun < Nud
      def parse(parser, tag, token)
        name = parser.expect("SYMBOL")[:lexeme]

        # Parse the parameters and slurpiness.
        params, slurpy = [] of String, false

        if parser.word!("(")
          parameter = -> do
            if parser.word!("*")
              unless slurpy = !slurpy
                parser.die("more than one '*' in function parameters")
              end

              "*"
            else
              parser.expect("SYMBOL")[:lexeme]
            end
          end

          params = parser
            .repeat(")", ",", unit: parameter)
            .compact
        end

        # Parse the 'given' appendix.
        given = [] of Quote

        if parser.word!("GIVEN")
          given = parser.repeat(sep: ",", unit: -> { parser.led(Precedence::ASSIGNMENT.value) })
        end

        # Parse the body.
        body = parser.word!("=") ? [parser.led] : block(parser)

        if body.empty?
          parser.die("empty function body illegal")
        end

        if params.empty? && !slurpy && !given.empty?
          parser.die("zero-arity functions cannot have a 'given'")
        end

        QFun.new(tag, name, params, body, given, slurpy)
      end
    end

    # Parses a 'queue' expression into a QQueue: `queue 1 + 2`.
    class PQueue < Nud
      def parse(parser, tag, token)
        QQueue.new(tag, parser.led)
      end
    end

    # Parses an 'ensure' expression into a QEnsure: `ensure 2 + 2 is 4`.
    class PEnsure < Nud
      def parse(parser, tag, token)
        QEnsure.new(tag, parser.led)
      end
    end

    # Parses a 'loop' statement into a QInfiniteLoop, QBaseLoop,
    # QStepLoop or QComplexLoop: `loop (x = 0 -> x < 10 -> x += 1) say(x)`
    class PLoop < Nud
      def parse(parser, tag, token)
        start : Quote?
        base : Quote?
        step : Quote?
        body : Quotes

        pres = Quotes.new

        if parser.word!("(")
          head = parser.repeat(")", sep: ";")

          case head.size
          when 0
            # (pass)
          when 1
            base = head.first
          when 2
            base, step = head[0], head[1]
          when 3
            start, base, step = head[0], head[1], head[2]
          else
            start, base, pres, step = head.first, head[1], head[2..-2], head.last
          end
        end

        body =
          if parser.word!("{")
            block(parser, opening: false)
          else
            @semicolon, _ = true, [parser.led]
          end

        if start && base && step
          QComplexLoop.new(tag, start, base, pres, step, body)
        elsif base && step
          QStepLoop.new(tag, base, step, body)
        elsif base
          QBaseLoop.new(tag, base, body)
        else
          QInfiniteLoop.new(tag, body)
        end
      end
    end

    class PQuote < Nud
      def parse(parser, tag, token)
        QQuote.new(tag, parser.led(Precedence::PREFIX.value))
      end
    end

    class PNud < Nud
      def parse(parser, tag, token)
        trigger = parser.expect("STRING")[:lexeme]
        unwrapped = trigger[1...-1]

        parser.expect("(")

        params = parser.repeat(")", ",", -> { parser.expect("SYMBOL")[:lexeme] })

        unless params && params.size == 1
          parser.die("invalid nud parameter list: expected one symbol")
        end

        # Let the trigger be a keyword.
        unless parser.keywords.includes?(unwrapped)
          parser.keywords << unwrapped
        end

        # Generate an actual parselet that will call this function
        # on a successful parse,
        #
        # NOTE: as each 'expose' is read by a different, fresh reader,
        # NUDs will naturally get defined in this different, fresh reader.
        # Obviously, we do not want that. What we want instead is for them
        # all to end up in the World's reader. Now, if we're a script,
        # World's reader is our only reader. If we're a module,
        # World's reader is the module's entry reader.
        parser.world.reader.@nud[unwrapped.upcase] = PNudTrigger.new(trigger)

        body = parser.word!("=") \
          ? [parser.led]
          : block(parser)

        # Translate this nud into a function definition for
        # the support of generics, etc.
        repr = QFun.new(tag, trigger, params, body, Quotes.new, false)

        # Visit this definition so the Machine knows about it.
        repr_model = parser.world.visit(repr)

        QModelCarrier.new(repr_model)
      end
    end

    class PNudTrigger < Nud
      def initialize(
        @trigger : String)
      end

      def parse(parser, tag, token)
        trigger = parser.world.context.fetch(@trigger)

        unless trigger
          parser.die(
            "trigger '#{@trigger}' is not in scope " \
            "(note: explicit read-time recursion not supported)")
        end

        model = parser
          .world
          .machine
          .call(trigger, [Str.new(token[:lexeme]).as(Model)])

        QModelCarrier.new(model)
      end
    end

    class PExpose < Nud
      def parse(parser, tag, token)
        pieces = parser.repeat(sep: ".", unit: -> { parser.expect("SYMBOL")[:lexeme] })

        QExpose.new(tag, pieces)
      end
    end

    class PDistinct < Nud
      def parse(parser, tag, token)
        pieces = parser.repeat(sep: ".", unit: -> { parser.expect("SYMBOL")[:lexeme] })

        QDistinct.new(tag, pieces)
      end
    end

    class PNext < Nud
      SCOPES = %w(FUN LOOP)

      def parse(parser, tag, token)
        args = Quotes.new

        if SCOPES.includes?(parser.word[:type])
          scope = parser.word![:lexeme]
        end

        if parser.is_nud?
          args = parser.repeat(sep: ",")
        end

        QNext.new(tag, scope, args)
      end
    end
  end
end
