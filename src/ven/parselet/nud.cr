module Ven
  module Parselet
    include Suite

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

        QNumber.new(tag, value.to_big_d)
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
      def initialize(@precedence : UInt8)
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
    # (iterative spread). Map spreads do not support naked
    # unary bodies: `|+_| [1, "2", false]` will die; one can
    # use `|(+_)| ...` instead.
    class PSpread < Nud
      def parse(parser, tag, token)
        kind, body =
          parser.is_led?(only: PBinary) \
            ? {:reduce, parser.word![:lexeme]}
            : {:map, QBlock.new(tag, [parser.led])}

        _, iterative = parser.expect("|"), !parser.word!(":").nil?

        kind == :reduce \
          ? QReduceSpread.new(tag, body.as(String), parser.led)
          : QMapSpread.new(tag, body.as(Quote), parser.led, iterative)
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
        context = if parser.word!("<")
          parser.before ">", -> do
            # Parses with the lowest precedence (FIELD), as
            # '>' is also a binary operator.
            parser.led(Precedence::FIELD.value)
          end
        end

        name = parser.expect("SYMBOL")[:lexeme]
        params = parser.word!("(") ? PFun.parameters(parser) : [] of String
        given = parser.word!("GIVEN") ? PFun.given(parser) : Quotes.new
        slurpy = params.includes?("*")
        body = parser.word!("=") ? [parser.led] : block(parser)

        if body.empty?
          parser.die("empty function body illegal")
        elsif params.empty? && !slurpy && !given.empty?
          parser.die("zero-arity functions cannot have a 'given'")
        elsif context
          params.unshift("$"); given.unshift(context)
        end

        QFun.new(tag, name, params, body, given, slurpy)
      end

      # Parses the 'given' appendix.
      def self.given(parser : Reader)
        parser.repeat(sep: ",", unit: -> { parser.led(Precedence::ASSIGNMENT.value) })
      end

      # Parses a list of `parameter`s. Performs all (or most
      # of) the required checks.
      #
      # *utility* determines whether to accept '*', '$', etc.,
      # as parameters.
      def self.parameters(parser : Reader, utility = true)
        this = parser.repeat(")", ",", unit: -> { parameter(parser, utility) })

        if this.count("*") > 1
          parser.die("more than one '*' in function parameters")
        elsif this.index("*").try(&.< this.size - 1)
          parser.die("slurpie ('*') must be at the end of the parameter list")
        elsif this.count("$") > 1
          parser.die("no support for multiple contexts yet")
        end

        this
      end

      # Reads a parameter. **Does not** check whether there
      # is one or multiple '*'s, etc.
      #
      # *utility* determines whether to read '*', '$', etc.
      def self.parameter(parser : Reader, utility = true)
        if utility
          parser.expect("*", "$", "_", "SYMBOL")[:lexeme]
        else
          parser.expect("SYMBOL", "_")[:lexeme]
        end
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
        QEnsure.new(tag, parser.led(Precedence::CONVERT.value))
      end
    end

    # Parses a 'loop' statement into
    # - a QInfiniteLoop: if `loop ...`;
    # - a QBaseLoop: if `loop (base) ...`;
    # - a QStepLoop: if `loop (base; step) ...`;
    # - a QComplexLoop: if `loop (start; base; step) ...`.
    class PLoop < Nud
      def parse(parser, tag, token)
        start : Quote?
        base : Quote?
        step : Quote?
        body : QBlock

        if parser.word!("(")
          head = parser.repeat(")", sep: ";")

          case head.size
          when 0
            # (pass)
          when 1
            base = head[0]
          when 2
            base, step = head[0], head[1]
          when 3
            start, base, step = head[0], head[1], head[2]
          else
            parser.die("malformed loop setup")
          end
        end

        repeatee = parser.led

        if repeatee.is_a?(QBlock)
          @semicolon = false
        end

        if start && base && step
          QComplexLoop.new(tag, start, base, step, repeatee)
        elsif base && step
          QStepLoop.new(tag, base, step, repeatee)
        elsif base
          QBaseLoop.new(tag, base, repeatee)
        else
          QInfiniteLoop.new(tag, repeatee)
        end
      end
    end

    # Parses a quotation: `'1`, `'(2 + 2)`, etc.
    class PQuote < Nud
      def parse(parser, tag, token)
        QQuote.new(tag, parser.led(Precedence::PREFIX.value))
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
    # ```ven
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
          ? PFun.parameters(parser, utility: false)
          : [] of String

        given = parser.word!("GIVEN") \
          ? PFun.given(parser)
          : Quotes.new

        namespace =
          if parser.word!("{")
            @semicolon = false

            parser.repeat "}", ";", -> do
              assignment = parser.led

              # Box blocks may only contain assignments.
              unless assignment.is_a?(QAssign)
                parser.die("only assignments are legal inside box blocks")
              end

              { assignment.target, assignment.value }
            end
          else
            {} of String => Quote
          end

        QBox.new(tag, name, params, given, namespace.to_h)
      end
    end

    # Parses a statement-level 'return': `return 1`, etc.:
    # ```ven
    # {
    #   return 1;
    # }
    # ```
    class PReturnStatement < Nud
      def parse(parser, tag, token)
        QReturnStatement.new(tag, parser.led)
      end
    end

    # Parses an expression-level 'return': `foo = return 1`,
    # `(return foo)`, etc.
    class PReturnExpression < Nud
      def parse(parser, tag, token)
        value = parser.led(Precedence::IDENTITY.value)

        QReturnExpression.new(tag, value)
      end
    end
  end
end
