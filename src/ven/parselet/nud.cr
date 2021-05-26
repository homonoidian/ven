require "./parselet"

module Ven::Parselet
  include Suite

  # A kind of parselet that is invoked by a null-denotated
  # word (a word that initiates an expression).
  abstract class Nud < Parselet
    # Invokes this parselet.
    #
    # *parser* is the parser that invoked this parselet; *tag*
    # is the location of the invokation; *token* is the null-
    # denotated word that invoked this parselet.
    def parse!(@parser, @tag, @token)
      # Reset the semicolon decision each parse!(), so as to
      # not get deceived by that made by a previous parse!().
      @semicolon = true

      parse
    end

    # Performs the parsing.
    #
    # All subclasses of `Nud` should implement this method.
    abstract def parse
  end

  # Reads a symbol into QSymbol.
  class PSymbol < Nud
    def parse
      symbol(@token)
    end
  end

  # Reads a number into QNumber.
  class PNumber < Nud
    def parse
      QNumber.new(@tag, lexeme.to_big_d)
    end
  end

  # Reads a string into QString.
  class PString < Nud
    # Escaped escape codes and what they should be
    # unescaped into.
    ESCAPES = {
      "\\$"  => "$",
      "\\e"  => "\e",
      "\\n"  => "\n",
      "\\r"  => "\r",
      "\\t"  => "\t",
      "\\\"" => "\"",
      "\\\\" => "\\",
    }

    def parse
      process(lexeme[1...-1])
    end

    # Unescapes valid escape codes and unpacks interpolation.
    def process(content : String) : QString | QBinary
      ending = 0
      offset = 0
      pieces = [QString.new(@tag, "")] of Quote

      loop do
        piece = pieces.last.as(QString)
        case pad = content[offset..]
        when .empty?
          break
        when .starts_with? Ven.regex_for(:STRING_ESCAPES)
          # Note: invalid escapes are skipped over.
          piece.value += ESCAPES[$0]? || $0
        when .starts_with? /\$(#{Ven.regex_for(:SYMBOL)}?)/
          # Note: "Hello, $" is identical to "Hello, $$".
          pieces << QRuntimeSymbol.new(@tag, $1.empty? ? "$" : $1)
          pieces << QString.new(@tag, "")
          ending = offset + $0.size
        else
          piece.value += pad[0]
          # Skip other characters.
          next offset += 1
        end
        offset += $0.size
      end

      # Reduce *pieces* down to a stitching operation (or
      # a single QString if *pieces* has only one).
      pieces.reduce do |memo, part|
        QBinary.new(@tag, "~", memo, part)
      end
    end
  end

  # Reads `_` into QUPop.
  class PUPop < Nud
    def parse
      QUPop.new(@tag)
    end
  end

  # Reads `&_` into QURef.
  class PURef < Nud
    def parse
      QURef.new(@tag)
    end
  end

  # Reads a regex pattern into QRegex.
  class PRegex < Nud
    def parse
      QRegex.new(@tag, lexeme[1...-1])
    end
  end

  # Reads a unary operation into QUnary.
  class PUnary < Nud
    def parse
      QUnary.new(@tag, type.downcase, led)
    end
  end

  # Reads a grouping (an expression wrapped in parens), or a
  # lambda (decides which one in the process).
  class PGroup < Nud
    def lambda(params = [] of String)
      # Notice how lambda consumes the rest of the expression.
      QLambda.new(@tag, params, led, "*".in? params)
    end

    def parse
      # Empty grouping is always an argumentless lambda:
      # ~> () ...
      return lambda if @parser.word!(")")

      # Agent is the expression that initiates a grouping.
      agent = led

      # Any agent but runtime symbol is always a grouping.
      unless agent.is_a?(QRuntimeSymbol)
        return @parser.before(")") { agent }
      end

      # Grouping with a comma in it is always a lambda.
      if @parser.word!(",")
        remaining = @parser.repeat(")", ",") do
          @parser.expect("SYMBOL", "*")[:lexeme]
        end

        return lambda([agent.value] + remaining)
      elsif @parser.expect(")")
        # ~> (x) + 1
        #        ^-- Clashes: `(x) { +1 }`
        #                  OR `x + 1`
        # Also:
        #   ~> (x) (y)
        #          ^--- is this a strangely-formulated call
        #               or a lambda body?
        if @parser.is_nud?(but: PUnary)
          return lambda([agent.value])
        end
      end

      # Fallback to the agent, i.e., the grouping behavior.
      agent
    end
  end

  # Reads a vector into QVector.
  class PVector < Nud
    def parse
      QVector.new(@tag, @parser.repeat("]", ","))
    end
  end

  # Reads a block into QBlock.
  class PBlock < Nud
    def parse
      QBlock.new(@tag, block(opening: false))
    end
  end

  # Reads a spread into QMapSpread or QReduceSpread.
  #
  # QMapSpread operator does not support naked unary; i.e.,
  # `|+_| [1, "2", false]` will die of read error. Hence a
  # grouping should be used: `|(+_)| [1, "2", false]`
  class PSpread < Nud
    def parse
      kind, body =
        @parser.is_led?(only: PBinary) \
          ? { :R, @parser.word![:lexeme] }
          : { :M, QBlock.new(@tag, [led]) }

      _, iterative = @parser.expect("|"), !!@parser.word!(":")

      kind == :M \
        ? QMapSpread.new(@tag, body.as(Quote), led, iterative)
        : QReduceSpread.new(@tag, body.as(String), led)
    end
  end

  # Reads an if expression into QIf.
  class PIf < Nud
    def parse
      cond = if? "(", @parser.before(")"), led
      succ = led
      fail = if? "ELSE", led

      QIf.new(@tag, cond, succ, fail)
    end
  end

  # Reads a function definition into QFun.
  class PFun < Nud
    def parse
      diamond = if? "<", diamond!

      name = symbol()
      params = if? "(", params!, [] of String
      givens = if? "GIVEN", given!, Quotes.new
      slurpy = "*".in?(params)
      body = if? "=", [body_source = led], block

      if body.empty?
        die("empty function body illegal")
      elsif body_source.is_a?(QBlock)
        # Don't need a semicolon if there's a block after '='.
        @semicolon = false
      elsif !slurpy && !params && givens
        die("zero-arity functions cannot have a 'given'")
      elsif diamond
        params.unshift("$"); givens.unshift(diamond)
      end

      QFun.new(@tag, name, params, body, givens, slurpy)
    end

    # Reads the diamond form.
    def diamond!
      @parser.before(">") { led(Precedence::FIELD) }
    end

    # Reads the body of a 'given' appendix.
    def given!
      @parser.repeat(sep: ",") { led(Precedence::ASSIGNMENT) }
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
      params = @parser.repeat(")", ",") { param!(utility) }

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
        ? @parser.expect("*", "$", "_", "SYMBOL")[:lexeme]
        : @parser.expect("_", "SYMBOL")[:lexeme]
    end
  end

  # Reads a 'queue' expression into QQueue: `queue 1 + 2`.
  class PQueue < Nud
    def parse
      QQueue.new(@tag, led)
    end
  end

  # Reads an 'ensure' expression into QEnsure: `ensure 2 + 2 is 4`.
  class PEnsure < Nud
    def parse
      QEnsure.new(@tag, led Precedence::CONVERT)
    end
  end

  # Reads a 'loop' statement into QInfiniteLoop,  QBaseLoop,
  # QStepLoop, or QComplexLoop.
  class PLoop < Nud
    def parse
      start : Quote?
      base  : Quote?
      step  : Quote?
      body  : QBlock

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
        QComplexLoop.new(@tag, start, base, step, repeatee)
      elsif base && step
        QStepLoop.new(@tag, base, step, repeatee)
      elsif base
        QBaseLoop.new(@tag, base, repeatee)
      else
        QInfiniteLoop.new(@tag, repeatee)
      end
    end
  end

  # Safety parselet for 'expose'. Always dies.
  class PExpose < Nud
    def parse
      @parser.die("please move this 'expose' to the start of your program")
    end
  end

  # Safety parselet for 'distinct'. Always dies.
  class PDistinct < Nud
    def parse
      @parser.die("this 'distinct' is meaningless")
    end
  end

  # Reads a 'next' expression.
  class PNext < Nud
    def parse
      scope = @parser.word!("FUN") || @parser.word!("LOOP")
      scope = scope[:lexeme] if scope
      QNext.new(@tag, scope, @parser.is_nud? ? @parser.repeat(sep: ",") : Quotes.new)
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
    def parse
      name = symbol()

      if name.is_a?(QRuntimeSymbol) && !name.value[0].uppercase?
        die("box name must be capitalized")
      end

      params = if? "(", params!, [] of String
      givens = if? "GIVEN", given!, Quotes.new
      fields = if? "{", block(opening: false), {} of QSymbol => Quote

      # Make sure that the `fields` block consists of assignments,
      # and construct the namespace.
      namespace = fields.map do |field|
        unless field.is_a?(QAssign) && (target = field.target).is_a?(QSymbol)
          die("expected an assignment to a symbol")
        end

        { target, field.value }
      end

      QBox.new(@tag, name, params, givens, namespace.to_h)
    end
  end

  # Reads a statement-level return.
  class PReturnStatement < Nud
    def parse
      QReturnStatement.new(@tag, led)
    end
  end

  # Reads an expression-level return.
  class PReturnExpression < Nud
    def parse
      QReturnExpression.new(@tag, led Precedence::IDENTITY)
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

    def parse
      defee, trigger = lead!
      params = if? "(", params!, [] of String
      expand = block

      if params.includes?("$")
        die("'$' has special meaning in read-time blocks")
      elsif params.includes?("_")
        die("nameless parses are illegal")
      end

      # Create the word.
      mkword defee, trigger

      # And define the macro.
      @parser.context[defee] = PNudMacro.new(params, expand)

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
      case @parser.word[:type]
      when "REGEX"
        { fresh, /^#{@parser.word![:lexeme]}/ }
      when "SYMBOL", .in?(@@subsidiary)
        { @parser.word[:lexeme].upcase, @parser.word![:lexeme] }
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
      @parser.context[type] = pattern
    end

    # Defines a new word. Its type will be *type*, and it will
    # be triggered by keyword *keyword*.
    #
    # Adds *keyword* to the list of subsidiary keywords.
    private def mkword(type : String, keyword : String)
      @@subsidiary << type
      @parser.context << keyword
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
    def initialize(@params : Array(String), body : Quotes)
      @body = QGroup.new(QTag.void, body)
    end

    def parse
      ReadExpansion.new(args!).visit(@body.clone)
    end

    # Reads the arguments of this nud macro by interpreting
    # its parameters (*@params*).
    #
    # Returns a hash of parameter names mapped to the corresponding
    # arguments. Tail slurpie (`*`) is stored under `$-tail`.
    private def args!
      @params.to_h do |name|
        name == "*" ? {"-tail", QVector.new(@tag, tail!)} : {name, led}
      end
    end

    # Reads the tail slurpie. Yields each expression to
    # the block.
    private def tail!
      leds = Quotes.new

      while @parser.is_nud?
        leds << led
      end

      leds
    end
  end
end
