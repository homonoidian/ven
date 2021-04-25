module Ven::Parselet
  include Suite

  # A parser that is invoked by a null-denotated token.
  abstract class Nud
    @precedence = 0_u8

    # Whether a semicolon must follow this nud.
    getter semicolon = true

    # Makes a nud with precedence *precedence* that uses
    # *parser* as the reader.
    def initialize(@parser : Reader, @precedence = 0_u8)
    end

    # Dies of read error with *message*, which should explain
    # why the error happened.
    def die(message : String)
      @parser.die(message)
    end

    # Returns the type of *token*.
    #
    # *token* defaults to `token`, which is the standard name
    # of the lead token in `parse`.
    macro type(token = token)
      {{token}}[:type]
    end

    # Returns the lexeme of *token*.
    #
    # *token* defaults to `token`, which is the standard name
    # of the lead token in `parse`.
    macro lexeme(token = token)
      {{token}}[:lexeme]
    end

    # Reads a symbol if *token* is nil (orelse uses the value
    # of *token*) and creates the corresponding symbol quote.
    def symbol(tag, token = nil) : QSymbol
      token ||= @parser.expect("$SYMBOL", "SYMBOL")

      case type
      when "$SYMBOL"
        QReadtimeSymbol.new(tag, lexeme)
      when "SYMBOL"
        QRuntimeSymbol.new(tag, lexeme)
      else
        raise "unknown symbol type"
      end
    end

    # Reads a block under the jurisdiction of this nud. Returns
    # the statements of this block. If *opening* is false, the
    # opening paren won't be read.
    def block(opening = true, @semicolon = false)
      @parser.expect("{") if opening
      @parser.repeat("}", unit: -> @parser.statement)
    end

    # Reads a led under the jurisdiction of this nud and with
    # the precedence of this nud.
    def led(precedence = @precedence)
      @parser.led(precedence)
    end

    # :ditto:
    def led(precedence : Precedence)
      led(precedence.value)
    end

    # Evaluates *consequtive* if read *word*; otherwise,
    # evaluates *alternative*.
    macro if?(word, then consequtive, else alternative = nil)
      @parser.word!({{word}}) ? {{consequtive}} : {{alternative}}
    end

    # Performs the parsing.
    abstract def parse(tag : QTag, token : Token)
  end

  # Reads a symbol into QSymbol.
  class PSymbol < Nud
    def parse(tag, token)
      symbol(tag, token)
    end
  end

  # Reads a number into QNumber.
  class PNumber < Nud
    def parse(tag, token)
      QNumber.new(tag, lexeme.to_big_d)
    end
  end

  # Reads a string into QString.
  class PString < Nud
    ESCAPES = {
      "\\n"  => "\n",
      "\\r"  => "\r",
      "\\t"  => "\t",
      "\\\"" => "\"",
      "\\\\" => "\\",
    }

    # Evaluates the escaped escape sequences in *source*.
    #
    # For example, `"1\\n2\\n"` will be evaluated to `"1\n2\n"`.
    def unescape(source : String)
      source.gsub(/\\([nrt"\\])/, ESCAPES)
    end

    def parse(tag, token)
      QString.new(tag, unescape lexeme[1...-1])
    end
  end

  # Reads `_` into QUPop.
  class PUPop < Nud
    def parse(tag, token)
      QUPop.new(tag)
    end
  end

  # Reads `&_` into QURef.
  class PURef < Nud
    def parse(tag, token)
      QURef.new(tag)
    end
  end

  # Reads a regex pattern into QRegex.
  class PRegex < Nud
    def parse(tag, token)
      QRegex.new(tag, lexeme[1...-1])
    end
  end

  # Reads a unary operation into QUnary.
  class PUnary < Nud
    def parse(tag, token)
      QUnary.new(tag, type.downcase, led)
    end
  end

  # Reads a grouping (an expression wrapped in parens).
  class PGroup < Nud
    def parse(tag, token)
      @parser.before(")")
    end
  end

  # Reads a vector into QVector.
  class PVector < Nud
    def parse(tag, token)
      QVector.new(tag, @parser.repeat("]", ","))
    end
  end

  # Reads a block into QBlock.
  class PBlock < Nud
    def parse(tag, token)
      QBlock.new(tag, block(opening: false))
    end
  end

  # Reads a spread into QMapSpread or QReduceSpread.
  #
  # QMapSpread operator does not support naked unary; i.e.,
  # `|+_| [1, "2", false]` will die of read error. Hence a
  # grouping should be used: `|(+_)| [1, "2", false]`
  class PSpread < Nud
    def parse(tag, token)
      kind, body =
        @parser.is_led?(only: PBinary) \
          ? { :R, @parser.word![:lexeme] }
          : { :M, QBlock.new(tag, [led]) }

      _, iterative = @parser.expect("|"), !!@parser.word!(":")

      kind == :M \
        ? QMapSpread.new(tag, body.as(Quote), led, iterative)
        : QReduceSpread.new(tag, body.as(String), led)
    end
  end

  # Reads an if expression into QIf.
  #
  # FIXME: `if (x) (a)` is interpreted as `if x(a)`, which
  # is wrong in this particular case.
  class PIf < Nud
    def parse(tag, token)
      cond = led
      succ = led
      fail = if?("ELSE", led)

      QIf.new(tag, cond, succ, fail)
    end
  end

  # Reads a function definition into QFun.
  class PFun < Nud
    def parse(tag, token)
      diamond = if? "<", diamond!

      name = symbol(tag)
      params = if? "(", params!, [] of String
      givens = if? "GIVEN", given!, Quotes.new
      slurpy = "*".in?(params)
      body = if? "=", [led], block

      if body.empty?
        die("empty function body illegal")
      elsif !slurpy && !params && givens
        die("zero-arity functions cannot have a 'given'")
      elsif diamond
        params.unshift("$"); givens.unshift(diamond)
      end

      QFun.new(tag, name, params, body, givens, slurpy)
    end

    # Reads the diamond form.
    def diamond!
      @parser.before ">", -> { led(Precedence::FIELD) }
    end

    # Reads the body of a 'given' appendix.
    def given!
      @parser.repeat(sep: ",", unit: -> { led(Precedence::ASSIGNMENT) })
    end

    # Reads a list of parameters.
    #
    # *utility* determines whether to allow '*', '$'.
    #
    # Ensures that there is one slurpie and it is at the end
    # of the list.
    #
    # Ensures that there is only one '$'.
    def params!(utility = true)
      params = @parser.repeat(")", ",", -> { param!(utility) })

      if params.count("*") > 1
        die("more than one slurpie in the parameter list")
      elsif params.index("*").try(&.< params.size - 1)
        die("the slurpie must be at the end of the parameter list")
      elsif params.count("$") > 1
        die("multiple contexts not supported")
      end

      params
    end

    # Reads a parameter.
    #
    # *utility* determines whether to allow '*', '$'.
    def param!(utility = true)
      utility \
        ? lexeme @parser.expect("*", "$", "_", "SYMBOL")
        : lexeme @parser.expect("_", "SYMBOL")
    end
  end

  # Reads a 'queue' expression into QQueue: `queue 1 + 2`.
  class PQueue < Nud
    def parse(tag, token)
      QQueue.new(tag, led)
    end
  end

  # Reads an 'ensure' expression into QEnsure: `ensure 2 + 2 is 4`.
  class PEnsure < Nud
    def parse(tag, token)
      QEnsure.new(tag, led Precedence::CONVERT)
    end
  end

  # Reads a 'loop' statement into QInfiniteLoop,  QBaseLoop,
  # QStepLoop, or QComplexLoop.
  class PLoop < Nud
    def parse(tag, token)
      start : Quote?
      base : Quote?
      step : Quote?
      body : QBlock

      if @parser.word!("(")
        head = @parser.repeat(")", sep: ";")

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
          die("malformed loop setup")
        end
      end

      repeatee = led

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

  # Reads an 'expose' statement into QExpose.
  class PExpose < Nud
    def parse(tag, token)
      QExpose.new(tag, pieces!)
    end

    # Reads pieces - a bunch of comma-separated SYMBOLs.
    def pieces!
      @parser.repeat(sep: ".", unit: -> { lexeme @parser.expect("SYMBOL") })
    end
  end

  # Reads a 'distinct' statement into QDistinct.
  class PDistinct < PExpose
    def parse(tag, token)
      QDistinct.new(tag, pieces!)
    end
  end

  # Reads a 'next' expression.
  class PNext < Nud
    def parse(tag, token)
      scope =
        @parser.word!("FUN") ||
        @parser.word!("LOOP")

      if scope
        scope = lexeme scope
      end

      QNext.new(tag, scope,
        @parser.is_nud? \
          ? @parser.repeat(sep: ",")
          : Quotes.new)
    end
  end

  # Reads a 'box' statement. Box name must be capitalized.
  # Boxes can define namespaces by providing a block, which
  # may contain solely assignments.
  #
  # ```ven
  #   box Foo(a, b) given num, str {
  #     x = a;
  #     y = x + b;
  #  }
  # ```
  class PBox < PFun
    def parse(tag, token)
      name = symbol(tag)

      if name.is_a?(QRuntimeSymbol) && !name.value[0].uppercase?
        die("box name must be capitalized")
      end

      params = if? "(", params!, [] of String
      givens = if? "GIVEN", given!, Quotes.new
      fields = if? "{", block(opening: false), {} of QSymbol => Quote

      # Make sure that the `fields` block consists of assignments,
      # and construct the namespace.
      namespace = fields.map do |field|
        field.is_a?(QAssign) \
          ? { field.target, field.value }
          : die("only assignments are legal in box blocks")
      end

      QBox.new(tag, name, params, givens, namespace.to_h)
    end
  end

  # Reads a statement-level return.
  class PReturnStatement < Nud
    def parse(tag, token)
      QReturnStatement.new(tag, led)
    end
  end

  # Reads an expression-level return.
  class PReturnExpression < Nud
    def parse(tag, token)
      QReturnExpression.new(tag, led Precedence::IDENTITY)
    end
  end

  # Reads and defines a new nud. Properly handles redefinition
  # of subsidiary nuds.
  #
  # ```ven
  # nud greet!(name) {
  #  say("Hi, " ~ $name);
  # }
  #
  # greet! "John Doe!"
  # ```
  class PDefineNud < PFun
    # A counter for unique names.
    @@fresh = 0
    # The keywords that were defined via 'nud', and therefore
    # the keywords that we are able to redefine.
    @@subsidiary = Set(String).new

    def parse(tag, token)
      defee, trigger = lead!
      params = if? "(", params!, [] of String
      expand = block

      if params.includes?("$")
        die("'$' has special meaning in read-time blocks")
      elsif params.includes?("_")
        die("nameless parses are illegal")
      end

      # Create the word:
      mkword defee, trigger

      # And define the macro:
      @parser.nud[defee] = PNudMacro.new(
        @parser,
        params,
        expand,
      )

      QVoid.new
    end

    # Parses the lead of this nud definition.
    #
    # The lead is either a regex pattern (word REGEX) or a
    # keyword (through word SYMBOL).
    #
    # Returns the type of the word that has to be defined and
    # the trigger.
    def lead! : {String, Regex | String}
      case type @parser.word
      when "REGEX"
        { fresh, /^#{lexeme(@parser.word!)}/ }
      when "SYMBOL", .in?(@@subsidiary)
        { lexeme(@parser.word).upcase, lexeme @parser.word! }
      else
        die("'nud': invalid lead: expected regex or symbol")
      end
    end

    # Generates a fresh lead name.
    private def fresh
      "__lead-#{@@fresh += 1}"
    end

    # Defines a new word. Its type will be *type*, and it will
    # be triggered by *pattern*.
    private def mkword(type : String, pattern : Regex)
      @parser.leads[type] = pattern
    end

    # Defines a new word. Its type will be *type*, and it will
    # be triggered by keyword *keyword*.
    #
    # Adds *keyword* to the list of subsidiary keywords.
    private def mkword(type : String, keyword : String)
      @@subsidiary << type; @parser.keywords << keyword
    end
  end

  # Represents a nud macro and expands it on a parse.
  #
  # When triggered, it interprets the nud parameters it was
  # initialized with and passes the results to the expansion
  # visitor (`ReadExpansion`).
  #
  # It is one of the **semantic nuds**.
  class PNudMacro < Nud
    def initialize(@parser, @params : Array(String), body : Quotes)
      @body = QGroup.new(QTag.void, body)
    end

    def parse(tag, token)
      ReadExpansion.new(args!).visit(@body.clone)
    end

    # Reads the arguments of this nud macro by interpreting
    # the parameters it accepts.
    #
    # Returns a hash of parameter names mapped to the corresponding
    # arguments. Tail slurpie (`*`) is stored under `$-tail`.
    def args!
      @params.to_h do |name|
        name == "*" ? {"-tail", QVector.new(QTag.void, tail!)} : {name, led}
      end
    end

    # Reads the tail slurpie. Yields each expression to
    # the block.
    def tail!
      leds = Quotes.new

      while @parser.is_nud?
        leds << led
      end

      leds
    end
  end
end
