require "./parselet"

module Ven::Parselet
  include Suite

  # A kind of parselet that is invoked by a null-denotated
  # word (a word that initiates an expression).
  abstract class Nud < Parselet
    # Invokes this parselet.
    #
    # *parser* is a reference to the `Reader` that invoked this
    # parselet. *tag* is the current location (see `QTag`).
    # *token* is the null-denotated word.
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

  # Reads a symbol into `QSymbol`.
  class PSymbol < Nud
    def parse
      symbol(@token)
    end
  end

  # Reads a number into `QNumber`.
  class PNumber < Nud
    def parse
      QNumber.new(@tag, lexeme.to_big_d)
    end
  end

  # Reads a string into `QString`.
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
          # Note: `"Hello, $"` is identical to `"Hello, $$"`,
          # which is the same as saying `"Hello" ~ $`.
          pieces << QRuntimeSymbol.new(@tag, $1.empty? ? "$" : $1)
          pieces << QString.new(@tag, "")
          ending = offset + $0.size
        else
          piece.value += pad[0]
          # Skip over the other characters.
          next offset += 1
        end
        offset += $0.size
      end

      # Reduce *pieces* down to one big stitching operation,
      # or return a single QString if *pieces* consist just
      # of that one string.
      pieces.reduce do |memo, part|
        QBinary.new(@tag, "~", memo, part)
      end
    end
  end

  # Reads `_` into `QSuperlocalTake`.
  class PSuperlocalTake < Nud
    def parse
      QSuperlocalTake.new(@tag)
    end
  end

  # Reads `&_` into `QSuperlocalTap`.
  class PSuperlocalTap < Nud
    def parse
      QSuperlocalTap.new(@tag)
    end
  end

  # Reads a regex pattern into `QRegex`.
  class PRegex < Nud
    def parse
      QRegex.new(@tag, lexeme)
    end
  end

  # Reads a unary operation into `QUnary`.
  class PUnary < Nud
    def parse
      QUnary.new(@tag, type.downcase, led)
    end
  end

  # Reads a grouping (an expression wrapped in parens), or a
  # lambda; decides which one in the process.
  class PGroup < Nud
    def parse
      # Empty grouping is always an argumentless lambda:
      # ~> () ...
      return lambda! if @parser.word!(")")

      # The subordinate is the expression that is inside a
      # grouping: in `(foo)`, `foo` is the subordinate.
      subordinate = led

      # Any subordinate except a runtime symbol is always
      # a grouping.
      unless subordinate.is_a?(QRuntimeSymbol)
        return @parser.before(")") { subordinate }
      end

      # Any grouping with a toplevel comma inside it is always
      # a lambda.
      if @parser.word!(",")
        params = @parser.repeat(")", ",") do
          @parser.expect("SYMBOL", "*").lexeme
        end

        return lambda!([subordinate.value] + params)
      elsif @parser.expect(")")
        # - Resolve `(x) + 1` as `x + 1`, **not** `(x) { +1 }`;
        # - Resolve `(x) (y)` as `(x) y`, **not** `x(y)`;
        # - Resolve `(x) / y` as `x / y` BUT `(x) * y` as
        #   `(x) { * y }` [MALFORMED] (here, '*' is the slurpie).
        return lambda!([subordinate.value]) if @parser.is_nud?(but: PUnary)
      end

      # Fall back to the grouping behavior.
      subordinate
    end

    # Reads the body of a lambda. Beware that lambdas consume
    # the rest of the expression (`() x = 1 and 2` is read
    # into a lambda).
    private def lambda!(params = [] of String)
      QLambda.new(@tag, params, led, "*".in? params)
    end
  end

  # Reads a vector into `QVector`.
  class PVector < Nud
    def parse
      items, filter = items!

      vector = QVector.new(@tag, items)

      unless filter.nil?
        return QFilterOver.new(@tag, vector, filter)
      end

      vector
    end

    # Reads the items. Returns a tuple of `{items, filter?}`.
    # Allows trailing commas. Does not allow filtering an
    # empty vector.
    private def items!
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

    # Reads the filter.
    private def filter!
      led
    end
  end

  # Reads a 'true' into `QTrue`.
  class PTrue < Nud
    def parse
      QTrue.new(@tag)
    end
  end

  # Reads a 'false' into `QFalse`.
  class PFalse < Nud
    def parse
      QFalse.new(@tag)
    end
  end

  # Reads a block into `QBlock`.
  class PBlock < Nud
    def parse
      QBlock.new(@tag, block(opening: false))
    end
  end

  # Reads a spread into `QMapSpread` or `QReduceSpread`.
  #
  # `QMapSpread` operator does not support naked unary; i.e.,
  # `|+_| [1, "2", false]` won't read. You can use a grouping
  # like so: `|(+_)| [1, "2", false]`
  class PSpread < Nud
    def parse
      if @parser.is_led?(only: PBinary)
        return QReduceSpread.new(@tag,
          @parser.word!.lexeme,
          @parser.after("|"),
        )
      end

      # `|_ + 1| ...` is the same as `|{ _ + 1 }| ...`
      operator = QBlock.new(@tag, [led])
      iterative = @parser.expect("|") && @parser.word!(":")

      QMapSpread.new(@tag, operator, led, !!iterative)
    end
  end

  # Reads an if expression into `QIf`.
  class PIf < Nud
    def parse
      cond = if? "(", @parser.before(")"), led
      succ = led
      fail = if? "ELSE", led

      QIf.new(@tag, cond, succ, fail)
    end
  end

  # Reads a function definition into `QFun`.
  class PFun < Nud
    def parse
      diamond = if? "<", diamond!
      name = symbol
      params = if? "(", params!, Quotes.new
      givens = if? "GIVEN", given!, Quotes.new

      # Keep the source led for meta (for us to know it was
      # a '='-function after all).
      body = if? "=", [equals = led], block

      die("empty function body illegal") if body.empty?

      # No need for a semicolon after a function whose
      # body is a block.
      @semicolon = false if equals.is_a?(QBlock)

      if params.empty? && !givens.empty?
        die("parameterless function has no use for 'given'")
      end

      # Unpack the diamond. Thanks to this, `fun<a> foo(b, c)`
      # becomes `fun foo($, b, c) given a`.
      if diamond
        params.unshift(QRuntimeSymbol.new(@tag, "$"))
        givens.unshift(diamond)
      end

      # `Parameters` takes care of validating the parameters,
      # making sure there is only a single `$`, `*`, etc.
      parameters = Parameters.new(
        Array(Parameter).new(params.size) do |index|
          # `Parameter` takes care of identifying whether the
          # parameter is `$`, `*`, a pattern, etc.
          Parameter.new(index, params[index], givens[index]?)
        end
      )

      QFun.new(@tag, name, parameters, body, !equals)
    end

    # Reads, and consequently returns, an expression enclosed
    # in function diamond (`<foo>`). **Assumes that the diamond
    # starter, '<', was already consumed.**
    def diamond!
      @parser.before(">") { led(Precedence::IDENTITY) }
    end

    # Reads, and consequently returns, an array of 'given'
    # quotes (`given <led>, <led>, ...`). **Assumes that
    # the 'given' keyword was already consumed.**
    def given!
      @parser.repeat(sep: ",") { led(Precedence::ASSIGNMENT) }
    end

    # Reads, and consequently returns, zero or more comma-
    # separated parameters, **assuming that the opening paren
    # was already consumed**.
    def params! : Quotes
      @parser.repeat(")", ",") do
        parameter = led

        # This kinda looks ugly here, but nah, no way to do
        # this otherwise.
        if parameter.is_a?(QReadtimeSymbol) && !in_readtime_context?
          die("readtime symbol (namely '#{parameter.value}') used " \
              "outside of readtime evaluation context")
        end

        parameter
      end
    end
  end

  # Reads a 'queue' expression into `QQueue`.
  class PQueue < Nud
    def parse
      QQueue.new(@tag, led)
    end
  end

  # Reads an 'ensure' assertion into `QEnsure`. Reads an
  # 'ensure' test into `QEnsureTest`.
  class PEnsure < Nud
    def parse
      subordinate = led(Precedence::CONVERT)

      unless @parser.word!("{")
        return QEnsure.new(@tag, subordinate)
      end

      # Ensure tests do not require a semicolon after
      # the block.
      @semicolon = false

      QEnsureTest.new(@tag, subordinate,
        @parser.repeat("}") { should! })
    end

    # Reads a should.
    private def should!
      @parser.expect("SHOULD")

      title = @parser.expect("STRING")
      cases = [] of Quote

      # Loop until the next "should". We can't use `repeat`
      # here, mainly because repeat consumes the stop & sep.
      until @parser.word?("SHOULD", "}")
        cases << led
        # If the current word is a semicolon, we consume it;
        # if a `should`, we leave it; if a `}`, we leave it
        # as well. In the last two cases, it'll break from
        # this loop immediately.
        if !@parser.word!(";") && !@parser.word?("SHOULD", "}")
          die("unexpected term")
        end
      end

      QEnsureShould.new(@tag, title.lexeme, cases).as(Quote)
    end
  end

  # Reads a 'loop' statement into either `QInfiniteLoop`,
  # `QBaseLoop`, `QStepLoop`, or `QComplexLoop`.
  class PLoop < Nud
    # Given a *base* quote (the first quote in the loop head), enacts the
    # decision to read a finite (`QBaseLoop`, `QStepLoop`, `QComplexLoop`)
    # loop. If *closing_paren* is true, expects a closing paren after the
    # loop head.
    protected def finite(base : Quote, closing_paren = false)
      start : Quote?
      step : Quote?

      # loop <led>,
      #           ^---- here
      if @parser.word!(",")
        step = led
      end

      # loop <led>, <led>,
      #                  ^--- here
      if @parser.word!(",")
        start = base
        base = step.not_nil!
        step = led
      end

      @parser.expect(")") if closing_paren

      body = led

      @semicolon = !body.is_a?(QBlock)

      if start && step
        QComplexLoop.new(@tag, start, base, step, body)
      elsif step
        QStepLoop.new(@tag, base, step, body)
      else
        QBaseLoop.new(@tag, base, body)
      end
    end

    # Given the *body* quote, enacts the decision to read an infinite loop.
    protected def infinite(body : Quote)
      @semicolon = !body.is_a?(QBlock)

      QInfiniteLoop.new(@tag, body)
    end

    def parse
      return finite(led, closing_paren: true) if @parser.word!("(")

      # Read the first quote. We don't know yet if it's the body
      # or the base of a condition.
      leader = led

      # Make sure we know what the user is talking about, and
      # switch to the appropriate branch.
      @parser.word?(",") || @parser.is_nud? ? finite(leader) : infinite(leader)
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

  # Reads a 'next', 'next fun', 'next led' expression
  # into `QNext`.
  class PNext < Nud
    def parse
      scope = @parser.word!("FUN") || @parser.word!("LOOP")

      QNext.new(@tag, scope.try(&.lexeme),
        # In case the next word is a nud, read the next
        # expressions: `next <fun|loop>? foo, bar, baz`.
        @parser.is_nud? ? @parser.repeat(sep: ",") : Quotes.new)
    end
  end

  # Reads a 'box' statement into `QBox`. Box name must be
  # capitalized. Boxes can declare fields with default values
  # by providing a block of assignments.
  class PBox < PFun
    def parse
      name = symbol
      params = if? "(", params!, Quotes.new
      givens = if? "GIVEN", given!, Quotes.new
      fields = if? "{", block(opening: false), {} of QSymbol => Quote

      if name.is_a?(QRuntimeSymbol) && !name.value[0].uppercase?
        die("box name must be capitalized")
      end

      # Go through the block, making sure each statement is
      # an assignment, and build the namespace.
      namespace = fields.map do |field|
        if !field.is_a?(QAssign)
          die("box block must consist of assignments only")
        elsif !field.target.is_a?(QSymbol)
          die("box block assignment's target must be a symbol")
        else
          {field.target.as(QSymbol), field.value}
        end
      end

      parameters = Parameters.new(
        Array(Parameter).new(params.size) do |index|
          # A restricted parameter will consider valid only
          # non-'$' & non-'*' `QRuntimeSymbol`, as well as
          # `QPatternEnvelope`.
          Parameter.new(index, params[index], givens[index]?, restricted: true)
        end
      )

      QBox.new(@tag, name, parameters, namespace.to_h)
    end
  end

  # Reads a statement-level return into `QReturnStatement`,
  # or a statement-level `return queue` into `QReturnQueue`.
  class PReturnStatement < Nud
    def parse
      if @parser.word!("QUEUE")
        QReturnQueue.new(@tag)
      else
        QReturnStatement.new(@tag, led)
      end
    end
  end

  # Reads an expression-level return into `QReturnExpression`,
  # or an expression-level `return queue` into `QReturnQueue`.
  class PReturnExpression < Nud
    def parse
      if @parser.word!("QUEUE")
        QReturnQueue.new(@tag)
      else
        # The IDENTITY precedence is more of a preference here,
        # as it's much more natural to write `return 1 and say(2)`
        # than `(return 1) and say(2)`.
        QReturnExpression.new(@tag, led Precedence::IDENTITY)
      end
    end
  end

  # Reads and defines a nud. Properly handles redefinition of
  # subordinate nuds.
  #
  # This parselet is abstract, and serves the purposes of
  # read-time interpretation. **It does not produce a quote**,
  # which implies, say, that it won't appear in `-j read`.
  class PDefineNud < PFun
    # A counter for unique symbol names.
    @@unique = 0

    def parse
      trigger_type, trigger = trigger!

      # If there's an identical Regex trigger in the reader
      # context already, update *word_type* to be that existing
      # trigger.
      if trigger.is_a?(Regex)
        if identical = @parser.context.trigger?(trigger)
          trigger_type = identical
        end
      end

      params = if? "(", params!, Quotes.new

      # The body ('=', or blocky) is read in a readtime context.
      # Take a look at `Parselet#in_readtime_context` to see
      # how it works.
      body = in_readtime_context { if? "=", [led], block }

      params = params.map do |param|
        case param
        when QRuntimeSymbol
          next param.value unless param.value == "$"

          die("cannot use '$' as the name of a nud parameter")
        when QSuperlocalTake
          die("nameless parses illegal")
        else
          die("invalid nud parameter expression")
        end
      end

      defword trigger_type, trigger

      @parser.context[trigger_type] = PNudMacro.new(params, body)

      # The reader pre-reads a word. Therefore for safety, we
      # need at least one word between the nud definition and
      # the word that it defines. Force a semicolon.
      @semicolon = true

      QVoid.new
    end

    # Reads the trigger of this nud definition. There are
    # two types of triggers: a regex pattern (word REGEX),
    # or a keyword (SYMBOL).
    #
    # Returns a tuple of `{trigger_type, trigger}`.
    def trigger!
      type, lexeme = @parser.word.type, @parser.word.lexeme

      # If *type* is a user-defined keyword, consume & return
      # out immediately.
      if @parser.context.keyword?(lexeme)
        return type, @parser.word!.lexeme
      end

      case type
      when "REGEX"
        {gentype, Regex.new(@parser.word!.lexeme)}
      when "SYMBOL"
        {lexeme.upcase, @parser.word!.lexeme}
      else
        die("'nud': bad trigger: expected regex or symbol")
      end
    rescue e : ArgumentError
      die("'nud': bad trigger regex: #{e.message}")
    end

    # Generates a fresh lead name.
    private def gentype
      "__trigger-#{@@unique += 1}"
    end

    # Defines a word *type*, which will be triggered by *pattern*.
    private def defword(type : String, pattern : Regex)
      @parser.context[type] = pattern
    end

    # Defines a word *type*, which will be triggered *keyword*.
    private def defword(type : String, keyword : String)
      @parser.context << keyword
    end
  end

  # Expands a nud macro when read.
  #
  # Makes sense of the nud parameters it was initialized with,
  # and passes the results of that to the expansion visitor
  # (see `ReadExpansion`).
  #
  # This parselet is abstract, and serves the purposes of
  # read-time interpretation. **It does not produce a quote**,
  # which implies, say, that it won't appear in `-j read`.
  class PNudMacro < Nud
    def initialize(@params : Array(String), @body : Quotes)
    end

    def parse
      definitions = {} of String => Quote

      # Regex triggers export their named captures into
      # their nud's definitions.
      if matches = @token.matches?
        matches.each do |capture, match|
          definitions[capture] = match ? QString.new(@tag, match) : QFalse.new(@tag)
        end
      end

      definitions.merge!(params!)

      expansion = ReadExpansion.new(self, @parser, definitions)

      # Transform the clone of the body, so as to not modify
      # the original (remember, there is only one instance
      # of this `PNudMacro` ever!)
      transformed = expansion.transform(@body.clone)

      # No need to nest blocks like that (this happens with
      # queue, as example)
      if transformed.size == 1 && (block = transformed.first.as? QBlock)
        transformed = block.body
      end

      statements = Quotes.new
      expressions = transformed.reject do |quote|
        case quote
        # Is this how good design looks like? XD
        when QFun,
             QBox,
             QInfiniteLoop,
             QBaseLoop,
             QStepLoop,
             QComplexLoop
          statements << quote
          # Do reject.
          true
        end
      end

      if !statements.empty? && expressions.empty?
        # Expanded to statements.
        QGroup.new(@tag, statements)
      elsif statements.empty? && !expressions.empty?
        # Expanded to expressions.
        QBlock.new(@tag, expressions)
      else
        # Expanded to both, or to nothing.
        die("macro expanded to statements & expressions at the " \
            "same time, or to nothing")
      end
    end

    # Reads the parameters of this nud macro.
    #
    # If this nud takes no parameters, this is a no-op. The
    # nud it is free to read the parameters itself.
    #
    # Returns a hash of parameter names mapped to arguments,
    # otherwise an empty hash.
    private def params!
      names = {} of String => Quote

      # If this nud takes no parameters, make the parentheses
      # optional (parameterless nuds likely do not want to
      # look like calls).
      return names if @params.empty? && !@parser.word?("(")

      args = @parser.after("(") do
        @parser.repeat(")", ",")
      end

      # Do an arity check. As nuds allow the slurpie, we need
      # to check for that too.
      unless @params.size == args.size || "*".in?(@params) && args.size >= @params.size
        die("malformed nud: expected #{@params.size}, " \
            "got #{args.size} argument(s)", on: @token)
      end

      @params.each_with_index do |param, index|
        if param == "*"
          # It'll break right after the slice.
          names[param] = QVector.new(@tag, args[index..])
        else
          names[param] = args[index]
        end
      end

      names
    end

    # Serializes this nud macro into a JSON object.
    #
    # The object contains three fields: *tweakable*, which
    # tells whether this object is tweakable, *params*, an
    # array of parameters of this nud macro, and *body*, a
    # serialized array of body Quotes.
    def to_json(json : JSON::Builder)
      json.object do
        json.field("tweakable", false)
        json.field("params", @params)
      end
    end
  end

  # Reads a pattern expression into `QPatternEnvelope`.
  class PPattern < Nud
    def parse
      QPatternEnvelope.new(@tag, led Precedence::FIELD)
    end
  end

  # Reads an immediate box statement into `QImmediateBox`.
  class PImmediateBox < Nud
    def parse
      @parser.expect("BOX")
      box = PBox.new
      quotes = box.parse!(@parser, @tag, @token)
      # Respect the semicolon decision made by the box parselet.
      @semicolon = box.semicolon
      QImmediateBox.new(@tag, quotes)
    end
  end

  # Reads a readtime envelope (`<...>`) into `QReadtimeEnvelope`,
  # or a hole (`<>`) into `QHole`.
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
        # Precedence > IDENTITY here, as IDENTITY includes
        # the '>' (greater than) operator, which conflicts
        # with the closing bracket '>'.
        led(Precedence::IDENTITY)
      })
    end
  end

  # Reads a map literal into `QMap`.
  class PMap < Nud
    def parse
      keys = Quotes.new
      vals = Quotes.new

      until @parser.word!("}")
        # The key can be string/symbol (normalized into string),
        # or a led **in parens**.
        if key = @parser.word!("STRING", "SYMBOL")
          keys << QString.new(@tag, key.lexeme)
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
