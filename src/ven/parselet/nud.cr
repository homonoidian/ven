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
      process(lexeme)
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
      QRegex.new(@tag, lexeme)
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
      QVector.new(@tag, *items!)
    end

    # Reads the items of this vector. Returns a tuple of
    # items followed by the filter (or nil).
    def items!
      items = Quotes.new
      filter = nil

      until @parser.word!("]")
        items << led
        # If met a '|' after an item, the rest is going
        # to be the filter.
        if @parser.word!("|")
          filter = filter!
          # There can be no items after the filter.
          break @parser.expect("]")
        elsif @parser.word!(",")
          next # pass
        end
      end

      {items, filter}
    end

    def filter!
      led
    end
  end

  # Reads a 'true'.
  class PTrue < Nud
    def parse
      QTrue.new(@tag)
    end
  end

  # Reads a 'false'.
  class PFalse < Nud
    def parse
      QFalse.new(@tag)
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
      if @parser.is_led?(only: PBinary)
        kind, body = {:R, @parser.word![:lexeme]}
      else
        kind, body = {:M, QBlock.new(@tag, [led])}
      end

      _, iterative = @parser.expect("|"), !!@parser.word!(":")

      if kind == :M
        QMapSpread.new(@tag, body.as(Quote), led, iterative)
      else
        QReduceSpread.new(@tag, body.as(String), led)
      end
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

      name = symbol
      params = if? "(", validate(params!), [] of String
      givens = if? "GIVEN", given!, Quotes.new

      # Get the body. Let it always be an Array, but, in case
      # it was an '='-function, store the source led so we
      # know it was one:
      body = if? "=", [equals = led], block

      # See how everything plays together.
      if body.empty?
        die("empty function body illegal")
      elsif equals.is_a?(QBlock)
        # Don't need a semicolon after the function if there's
        # a block after '=':
        @semicolon = false
      elsif params.empty? && !givens.empty?
        die("there is no reason to have 'given' here")
      elsif diamond && !"$".in?(params)
        # Unpack the diamond, so `fun<a> foo(b, c)` becomes
        # `fun foo($, b, c) given a`.
        params.unshift("$")
        givens.unshift(diamond)
      end

      # Build the parameters.
      parameters = Array(Parameter).new(params.size) do |index|
        param = params[index]

        Parameter.new(index, param,
          givens[index]?,
          param == "*",
          param == "$",
        )
      end

      QFun.new(@tag, name, Parameters.new(parameters), body, !equals)
    end

    # Reads a diamond.
    #
    # Assumes that the diamond starter, '<', was already
    # consumed.
    def diamond!
      @parser.before(">") { led(Precedence::IDENTITY) }
    end

    # Reads a 'given' appendix (`given <led>, <led>, <led>`).
    #
    # Assumes that the 'given' keyword itself was already
    # consumed.
    def given!
      @parser.repeat(sep: ",") { led(Precedence::ASSIGNMENT) }
    end

    # Validates *params*, an array of raw parameters.
    #
    # Dies if validation failed. If OK, returns the
    # parameters back.
    def validate(params : Array(String)) : Array(String)
      if params.count("*") > 1
        die("more than one slurpie in the parameter list")
      elsif params.index("*").try(&.< params.size - 1)
        die("the slurpie must be at the end of the parameter list")
      elsif params.count("$") > 1
        die("multiple contexts not supported")
      end

      params
    end

    # Reads zero or more comma-separated parameters. Assumes
    # that the opening paren was already consumed, and the
    # closing one isn't.
    #
    # *special*, if false, forbids the usage of the special
    # parameters '*' and '$'.
    #
    # Returns raw parameter list.
    def params!(special = true) : Array(String)
      @parser.repeat(")", ",") { param!(special) }
    end

    # Reads one parameter.
    #
    # *special*, if false, forbids the usage of the special
    # parameters '*' and '$'.
    def param!(special = true) : String
      if special
        @parser.expect("*", "$", "_", "SYMBOL")[:lexeme]
      else
        @parser.expect("_", "SYMBOL")[:lexeme]
      end
    end
  end

  # Reads a 'queue' expression into QQueue.
  class PQueue < Nud
    def parse
      QQueue.new(@tag, led)
    end
  end

  # Reads an 'ensure' assertion into QEnsure. Reads an 'ensure'
  # test into QEnsureTest.
  class PEnsure < Nud
    def parse
      agent = led(Precedence::CONVERT)

      return QEnsure.new(@tag, agent) unless @parser.word!("{")

      @semicolon = false

      # If we have a block opening after the agent, we're
      # QEnsureTest:
      #
      # ~> ensure <...> {
      #  we are here ---^
      shoulds = @parser.repeat(stop: "}") { should }

      QEnsureTest.new(@tag, agent, shoulds)
    end

    # Reads a should.
    private def should : Quote
      @parser.expect("SHOULD")

      section = @parser.expect("STRING")
      cases = @parser.repeat(sep: ";")

      QEnsureShould.new(@tag, section[:lexeme], cases).as(Quote)
    end
  end

  # Reads a 'loop' statement into QInfiniteLoop,  QBaseLoop,
  # QStepLoop, or QComplexLoop.
  class PLoop < Nud
    def parse
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
      scope &&= scope[:lexeme]
      QNext.new(@tag, scope, @parser.is_nud? ? @parser.repeat(sep: ",") : Quotes.new)
    end
  end

  # Reads a 'box' statement. Box name must be capitalized.
  # Boxes can declare fields with default values by providing
  # a block. This block must consist solely of assignments.
  #
  # ```ven
  #   box Foo(a, b) given num, str {
  #     x = a;
  #     y = x + b;
  #  }
  # ```
  class PBox < PFun
    def parse
      name = symbol
      params = if? "(", validate(params!), [] of String
      givens = if? "GIVEN", given!, Quotes.new
      fields = if? "{", block(opening: false), {} of QSymbol => Quote

      # See if everything conforms to the norms.
      if name.is_a?(QRuntimeSymbol) && !name.value[0].uppercase?
        die("box name must be capitalized")
      elsif params.count('$') != 0
        die("boxes cannot accept a '$'")
      end

      # Build the namespace, making sure the box block is
      # correct on the way.
      namespace = fields.map do |field|
        unless field.is_a?(QAssign) && (target = field.target).is_a?(QSymbol)
          die("box block must consist of assignments only")
        end
        {target, field.value}
      end

      # Build the parameters.
      parameters = Array(Parameter).new(params.size) do |index|
        param = params[index]

        Parameter.new(index, param,
          givens[index]?,
          param == "*",
          param == "$",
        )
      end

      QBox.new(@tag, name, Parameters.new(parameters), namespace.to_h)
    end
  end

  # Reads a statement-level return. Reads a statement-level
  # `return queue` expression.
  class PReturnStatement < Nud
    def parse
      if !!@parser.word!("QUEUE")
        QReturnQueue.new(@tag)
      else
        QReturnStatement.new(@tag, led)
      end
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
    # A counter for unique symbol names.
    @@fresh = 0
    # The keywords that were defined via 'nud', and therefore
    # the keywords that we should be able to redefine.
    @@subsidiary = Set(String).new

    def parse
      # Word trigger is either a Regex or a String (and
      # therefore keyword).
      word_type, word_trigger = lead!

      # To define a parametric nud (the one that looks like
      # a function call), you need to provide at least one
      # parameter.
      params = if? "(", params!, [] of String

      # The body ('=' or blocky) is read in a readtime context.
      # Take a look at `Parselet#in_readtime_context` to learn
      # more.
      body = in_readtime_context { if? "=", [led], block }

      if params.includes?("$")
        die("cannot use '$' as the name of a nud parameter")
      elsif params.includes?("_")
        die("nameless parses illegal")
      end

      if word_trigger.is_a?(Regex)
        # If there's an identical Regex trigger in the reader
        # context, redefine our *word_type* to be that trigger.
        if identical_trigger_type = @parser.context.trigger?(word_trigger)
          word_type = identical_trigger_type
        end
      end

      defword word_type, word_trigger

      @parser.context[word_type] = PNudMacro.new(params, body)

      # Force semicolon, as there is some bad design pre-
      # reading a word. For correctness, we need at least
      # one word between the nud definition and the word
      # defined by it.
      @semicolon = true

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
        {fresh, Regex.new(@parser.word![:lexeme])}
      when "SYMBOL", .in?(@@subsidiary)
        {@parser.word[:lexeme].upcase, @parser.word![:lexeme]}
      else
        die("'nud': bad lead: expected regex or symbol")
      end
    rescue e : ArgumentError
      die("'nud': bad lead regex: #{e.message}")
    end

    # Generates a fresh lead name.
    private def fresh
      "__lead-#{@@fresh += 1}"
    end

    # Defines a new word. Its type will be *type*, and it will
    # be triggered by *pattern*.
    private def defword(type : String, pattern : Regex)
      @parser.context[type] = pattern
    end

    # Defines a new word. Its type will be *type*, and it will
    # be triggered by keyword *keyword*.
    #
    # Adds *keyword* to the list of subsidiary keywords.
    private def defword(type : String, keyword : String)
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
      definitions = {} of String => Quote

      # Trigger words export named captures. Import them into
      # the *definitions*.
      if exports = @token[:exports]
        exports.each do |capture, match|
          definitions[capture] = match ? QString.new(@tag, match) : QFalse.new(@tag)
        end
      end

      # Clone: we do not want to modify the original body.
      ReadExpansion.new(definitions.merge(rest!)).transform(@body.clone)
    end

    # Reads the rest of this nud macro by interpreting its
    # parameters, if any.
    #
    # If this nud takes no parameters, it is free to parse
    # them itself.
    #
    # Returns a hash of parameter names mapped to arguments,
    # or an empty hash if there weren't any parameters.
    private def rest!
      names = {} of String => Quote

      # If this nud takes no parameters, make the parentheses
      # optional (parameterless nuds likely do not want to
      # look like calls).
      if @params.empty? && @parser.word[:type] != "("
        return names
      end

      args = @parser.after("(") { @parser.repeat(")", ",") }

      # Do an arity check. As nuds allow the slurpie, we
      # need to check for that too.
      unless @params.size == args.size || "*".in?(@params) && args.size >= @params.size
        die("malformed nud: expected #{@params.size}, got #{args.size} argument(s)")
      end

      @params.each_with_index do |param, index|
        if param == "*"
          names[param] = QVector.new(@tag, args[index..], nil)
        else
          names[param] = args[index]
        end
      end

      names
    end

    # Serializes this nud macro into a JSON object.
    #
    # The object contains three fields: *tweakable*, which
    # tells to outsiders whether this object is tweakable,
    # *params*, an array of parameters of this nud macro,
    # and *body*, a serialized array of body Quotes.
    def to_json(json : JSON::Builder)
      json.object do
        json.field("tweakable", false)
        json.field("params", @params)
        json.field("body", @body.body)
      end
    end
  end

  # Reads a pattern (pattern lambda) expression and wraps
  # it in `QPatternEnvelope`.
  class PPattern < Nud
    def parse
      QPatternEnvelope.new(@tag, led Precedence::FIELD)
    end
  end

  # Reads an immediate box statement. Immediate box statements
  # allow to define and immediately instantiate a box.
  class PImmediateBox < Nud
    def parse
      @parser.expect("BOX")
      box = PBox.new
      quotes = box.parse!(@parser, @tag, @token)
      # Forward the semicolon decision made by the box
      # parselet upwards.
      @semicolon = box.semicolon
      QImmediateBox.new(@tag, quotes)
    end
  end

  # Reads a readtime envelope. Readtime envelopes bring
  # a subset of Ven to readtime.
  #
  # ```ven
  # nud foo(a, b) {
  #   <a + b> # QReadtimeEnvelope
  # };
  #
  # foo(1, 2) # expands to 3
  # ```
  class PReadtimeEnvelope < Nud
    def parse
      unless in_readtime_context?
        die("readtime envelope used outside of readtime evaluation context")
      end

      # For convenience, do not require a semicolon.
      @semicolon = false

      # If the envelope is immediately closed (`<>`), it's
      # a hole.
      return QHole.new(@tag) if @parser.word!(">")

      QReadtimeEnvelope.new(@tag, @parser.before(">") {
        # Precedence more than IDENTITY here, as IDENTITY
        # includes the '>' (greater than) operator, which
        # conflicts with the closing bracket '>'. Same with
        # 'fun's diamond.
        led(Precedence::IDENTITY)
      })
    end
  end

  # Reads a map literal: `%{"a" 1, "b" 2}`, `%{"foo" 1 "bar" 2}`.
  class PMap < Nud
    def parse
      keys = Quotes.new
      vals = Quotes.new

      until @parser.word!("}")
        # If the key is a string or a symbol, normalize to
        # string: `%{a 1 b 2}`. Alternatively, parse led in
        # parens (so you can use symbol & any other value
        # as key: `%{(a) 1 (b) 2}`)
        if key = @parser.word!("STRING", "SYMBOL")
          keys << QString.new(@tag, key[:lexeme])
        elsif @parser.expect("(")
          keys << @parser.before(")")
        end

        vals << led

        # Optionally read a ','.
        @parser.word!(",")
      end

      QMap.new(@tag, keys, vals)
    end
  end
end
