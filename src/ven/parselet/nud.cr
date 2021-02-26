module Ven
  module Parselet
    include Component

    # Null-denotated token parser works with tokens that are
    # not preceded by a quote.
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

      # Returns whether this nud requires a semicolon.
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
    # *quote* is the quote this Nud will produce; *argument*
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
        value = token[:lexeme]

        if value.ends_with?("_")
          parser.die("trailing '_' in number")
        end

        QNumber.new(tag, value.delete('_'))
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

    # Parses a unary operation into a QUnary: `+12.34`,
    # `~[1, 2, 3]`, `-true`, etc.
    class PUnary < Nud
      def initialize(
        @precedence : UInt8)
      end

      def parse(parser, tag, token)
        QUnary.new(tag, token[:type].downcase, parser.led(@precedence))
      end
    end

    # Parses a grouping: `(2 + 2)`, etc.
    class PGroup < Nud
      def parse(parser, tag, token)
        parser.before(")")
      end
    end

    # Parses a vector into a QVector: `[]`, `[1]`, `[4, 5, 6,]`,
    # etc.
    class PVector < Nud
      def parse(parser, tag, token)
        QVector.new(tag, parser.repeat("]", ","))
      end
    end

    # Parses a spread into a QSpread: `|+| [1, 2, 3]` (reduce
    # spread), `|_ is 5| [1, 2, 3]` (map spread), `|say(_)|: [1, 2, 3]`
    # (iterative spread). Lambda spreads do not support naked
    # unary bodies: `|+_| [1, "2", false]` will die; one can
    # use `|(+_)| ...` instead.
    class PSpread < Nud
      def parse(parser, tag, token)
        kind, body =
          parser.is_led?(only: PBinary) \
            ? {:binary, parser.word![:lexeme]}
            : {:lambda, parser.led}

        _, iterative = parser.expect("|"), !parser.word!(":").nil?

        kind == :binary \
          ? QBinarySpread.new(tag, body.as(String), parser.led)
          : QLambdaSpread.new(tag, body.as(Quote), parser.led, iterative)
      end
    end

    # Parses a block into a QBlock: `{ 5 + 5; x = say(3); x }`,
    # etc.
    class PBlock < Nud
      def parse(parser, tag, token)
        QBlock.new(tag, block(parser, opening: false))
      end
    end

    # Parses an 'if' expression into a QIf: `if true say("Yay!")`,
    # `if false say("Nay!") else say("Boo!")`, etc.
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

        params = parser.word!("(") \
          ? PFun.parameters(parser)
          : [] of String

        given  = parser.word!("GIVEN") \
          ? PFun.given(parser)
          : Quotes.new

        slurpy = params.includes?("*")

        body = parser.word!("=") \
          ? [parser.led]
          : block(parser)

        if body.empty?
          parser.die("empty function body illegal")
        elsif params.empty? && !slurpy && !given.empty?
          parser.die("zero-arity functions cannot have a 'given'")
        end

        QFun.new(tag, name, params, body, given, slurpy)
      end

      # Parses the 'given' appendix.
      def self.given(parser : Reader)
        parser.repeat(sep: ",", unit: -> { parser.led(Precedence::ASSIGNMENT.value) })
      end

      # Parses a list of `parameter`s. Makes sure there are
      # either no '*' or only one '*'.
      def self.parameters(parser : Reader)
        this = parser.repeat(")", ",", unit: -> { parameter(parser) })

        this.count("*") > 1 \
          ? parser.die("more than one '*' in function parameters")
          : this
      end

      # Reads a parameter (symbol or '*'). Does not check
      # whether there is one or multiple '*'s.
      macro parameter(parser)
        {{parser}}.expect("*", "SYMBOL")[:lexeme]
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

    # Parses a 'loop' statement into
    #   + a QInfiniteLoop: if `loop ...` or `loop { ... }`;
    #   + a QBaseLoop: if `loop (base) ...` or `loop (base) { ... }`;
    #   + a QStepLoop: if `loop (base; step) ...` or `loop (base; step) { ... }`;
    #   + a QComplexLoop: if `loop (start; base; ...; step) ...` or
    #     `loop (start; base; ...; step) { ... }`.
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

    # Parses a quotation: `'1`, `'(2 + 2)`, etc.
    class PQuote < Nud
      def parse(parser, tag, token)
        QQuote.new(tag, parser.led(Precedence::PREFIX.value))
      end
    end

    # Parses a nud statement and defines a runtime nud:
    # `nud "name"(value) = ...` or `nud "name"(value) { ... }`.
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

        # Create a trigger parselet that will call the trigger
        # function if parsed successfully.
        #   NOTE: each 'expose' is read by a different, fresh reader;
        # the NUDs of 'expose' will naturally get defined in this
        # different, fresh reader. Obviously, we do not want that.
        #   What we want is for them all to end up in the World's
        # reader. Now, if we're a script, World's reader is our
        # only reader. If we're a module, World's reader is the
        # origin reader.

        parser.world.reader.@nud[unwrapped.upcase] = PNudTrigger.new(trigger)

        body = parser.word!("=") \
          ? [parser.led]
          : block(parser)

        # Translate this nud into a function definition for
        # the generics etc. (XXX)
        repr = QFun.new(tag, trigger, params, body, Quotes.new, false)

        # Visit this definition so our Machine knows about it.
        repr_model = parser.world.visit(repr)

        QModelCarrier.new(repr_model)
      end
    end

    # A trigger parselet that will call the trigger function
    # (named after *@trigger*.)
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

    # Parses an 'expose' statement into a QExpose: `expose a.b.c`,
    # `expose foo` etc.
    class PExpose < Nud
      def parse(parser, tag, token)
        pieces = parser.repeat(sep: ".", unit: -> { parser.expect("SYMBOL")[:lexeme] })

        QExpose.new(tag, pieces)
      end
    end

    # Parses a 'distinct' statement into a QDistinct: `distinct a.b.c`,
    # `distinct foo` etc.
    class PDistinct < Nud
      def parse(parser, tag, token)
        pieces = parser.repeat(sep: ".", unit: -> { parser.expect("SYMBOL")[:lexeme] })

        QDistinct.new(tag, pieces)
      end
    end

    # Parses a 'next' expression, which can have different scopes:
    # `next` and `next 1, 2, 3`, `next fun` and `next loop`,
    # `next fun 1, 2, 3` and `next loop 1, 2, 3`, etc.
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

    # Parses a 'box' statement: `box Foo`. Box name must be
    # capitalized. A box can accept parameters the way funs
    # accept them: `box Foo(a, b) given num`, etc. Boxes can
    # have blocks (namespaces), which may contain solely
    # assignments (`PAssign`s):
    # ```
    #   box Foo {
    #     x = 0;
    #     y = x;
    #  }
    # ```
    class PBox < Nud
      def parse(parser, tag, token)
        name = parser.expect("SYMBOL")[:lexeme]

        unless name.chars.first.uppercase?
          parser.die("illegal box name: must be capitalized")
        end

        params = parser.word!("(") \
          ? PFun.parameters(parser)
          : [] of String

        given = parser.word!("GIVEN") \
          ? PFun.given(parser)
          : Quotes.new

        namespace =
          if parser.word!("{")
            # We do not require the semicolon from now on.
            @semicolon = false

            parser.repeat "}", ";", -> do
              it = parser.led

              # Box blocks may only contain assignments.
              unless it.is_a?(QAssign)
                parser.die("statements other than assignment illegal in box blocks")
              end

              {it.target, it.value}
            end
          else
            {} of String => Quote
          end

        QBox.new(tag, name, params, given, namespace.to_h)
      end
    end
  end
end
