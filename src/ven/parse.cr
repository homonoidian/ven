require "./parselet/*"
require "./component/quote"
require "./component/error"

module Ven
  # Return the regex pattern for a lexeme *name*. Available
  # *name*s are: `:SYMBOL`, `:STRING`, `:NUMBER`, `:SPECIAL`,
  # `:IGNORE`.
  macro regex_for(name)
    {% if name == :SYMBOL %}
      # &?_ is here because it should be handled like a keyword
      /([_a-zA-Z](\-?\w)+|[a-zA-Z])[?!]?|&?_/
    {% elsif name == :STRING %}
      /"([^\n"\\]|\\[ntr\\"])*"/
    {% elsif name == :REGEX %}
      /`([^\\`]|\\.)*`/
    {% elsif name == :NUMBER %}
      /\d*\.\d+|[1-9]\d*|0/
    {% elsif name == :SPECIAL %}
      /--|\+\+|=>|[-+*\/~<>]=|[-<>~+*\/()[\]{},:;=?.|]/
    {% elsif name == :IGNORE %}
      /([ \n\r\t]+|#[^\n]*)/
    {% else %}
      {{ raise "no pattern for #{name}" }}
    {% end %}
  end

  private RX_SYMBOL  = /^#{regex_for(:SYMBOL)}/
  private RX_STRING  = /^#{regex_for(:STRING)}/
  private RX_REGEX  = /^#{regex_for(:REGEX)}/
  private RX_NUMBER  = /^#{regex_for(:NUMBER)}/
  private RX_IGNORE  = /^#{regex_for(:IGNORE)}/
  private RX_SPECIAL = /^#{regex_for(:SPECIAL)}/
  private KEYWORDS   = %w(
    _ &_
    is
    in
    if
    not
    fun
    else
    until
    while
    queue
    given
    ensure
  )

  alias Token = {
    type: String,
    raw: String,
    line: Int32
  }

  enum Precedence
    ZERO
    ASSIGNMENT
    CONDITIONAL
    IDENTITY
    ADDITION
    PRODUCT
    POSTFIX
    PREFIX
    CALL
    FIELD
  end

  class Parser
    include Component

    getter tok

    @tok : Token = { type: "START", raw: "start anchor", line: 1 }

    def initialize(@file : String, @src : String)
      @buf = ""
      @pos = 0
      @led = {} of String => Parselet::Led
      @nud = {} of String => Parselet::Nud
      @stmt = {} of String => Parselet::Nud
      @line = 1
      @tok = accept
    end

    def die(message : String)
      raise ParseError.new(@tok, @file, message)
    end

    private def match(pattern : Regex) : Bool?
      if pattern =~ @src[@pos..]
        @pos += $0.size
        @buf = $0
        return true
      end
    end

    private macro token(type)
      { type: {{type}}, raw: @buf, line: @line }
    end

    private def accept
      loop do
        return case
        when match(RX_IGNORE)
          next @line += @buf.count("\n")
        when match(RX_SPECIAL)
          token(@buf.upcase)
        when match(RX_SYMBOL)
          token(KEYWORDS.includes?(@buf) ? @buf.upcase : "SYMBOL")
        when match(RX_NUMBER)
          token("NUMBER")
        when match(RX_STRING)
          token("STRING")
        when match(RX_REGEX)
          token("REGEX")
        when @pos == @src.size
          token("EOF")
        else
          raise ParseError.new(@src[@pos].to_s, @line, @file, "malformed input")
        end
      end
    end

    private def precedence?
      # Symbol `x` is an operator if met in a position where
      # infix is expected.
      if @tok[:type] == "SYMBOL" && @tok[:raw] == "x"
        @tok = {type: "X", raw: "x", line: @tok[:line]}
      end

      (@led.fetch(@tok[:type]) { return 0 }).precedence
    end

    def consume
      @tok, _ = accept, @tok
    end

    def consume(type : String)
      if @tok[:type] == type
        consume
      end
    end

    def expect(*types : String)
      return consume if types.includes?(@tok[:type])

      types = types.map do |x|
        "'#{x}'"
      end

      die("expected #{types.join(", ")}")
    end

    def before(type : String, unit : -> Quote = ->infix)
      value = unit.call; expect(type); value
    end

    def repeat(stop : String? = nil, sep : String? = nil, unit : -> T = ->infix) forall T
      result = [] of T

      unless stop || sep
        raise "expected stop or sep or stop and sep; none given"
      end

      until stop && consume(stop)
        result << unit.call
        if stop && sep
          consume(sep) ? next : break expect(stop, sep)
        elsif sep && !consume(sep)
          break
        elsif stop && consume(stop)
          break
        end
      end

      result
    end

    def prefix : Quote
      @nud
        .fetch(@tok[:type]) { die("malformed term") }
        .parse(self, QTag.new(@file, @line), consume)
    end

    def infix(level = Precedence::ZERO.value) : Quote
      left = prefix

      while level < precedence?
        tag = QTag.new(@file, @line)
        operator = consume
        left = @led[(operator[:type])].parse(self, tag, left, operator)
      end

      left
    end

    def statement(trail = "EOF", detrail = true) : Quote
      if parselet = @stmt.fetch(@tok[:type], false)
        parselet
          .as(Parselet::Nud)
          .parse(self, QTag.new(@file, @line), consume)
      else
        expression = infix
        if consume(";") || detrail && consume(trail) || (@tok[:type] == trail)
          expression
        else
          # Just so expected error looks nice
          expect(";", trail)
        end.as(Quote)
      end
    end

    def start : Quotes
      repeat("EOF", unit: ->statement)
    end

    def nud(only pick : Parselet::Nud.class ? = nil)
      @nud.reject { |_, nud| pick.nil? ? false : nud.class != pick }
    end

    def led(only pick : Parselet::Led.class ? = nil)
      @led.reject { |_, led| pick.nil? ? false : led.class != pick }
    end

    private macro defnud(type, *tail, storage = @nud, precedence = PREFIX)
      {% unless tail.first.is_a?(StringLiteral) %}
        {{storage}}[{{type}}] = {{tail.first}}.new
      {% else %}
        {% for prefix in [type] + tail %}
          {{storage}}[{{prefix}}] = Parselet::Unary.new(Precedence::{{precedence}}.value)
        {% end %}
      {% end %}
    end

    private macro defled(type, *tail, common = nil, precedence = ZERO)
      {% unless tail.first.is_a?(StringLiteral) || !tail.first %}
        @led[{{type}}] = {{tail.first}}.new(Precedence::{{precedence}}.value)
      {% else %}
        {% for infix in [type] + tail %}
          {% unless common %}
            @led[{{infix}}] = Parselet::Binary.new(Precedence::{{precedence}}.value)
          {% else %}
            @led[{{infix}}] = {{common}}.new(Precedence::{{precedence}}.value)
          {% end %}
        {% end %}
      {% end %}
    end

    private macro defstmt(type, *tail)
      defnud({{type}}, {{*tail}}, storage: @stmt)
    end

    def register
      # Prefixes (NUDs):
      defnud("+", "-", "~", "NOT")
      defnud("IF", Parselet::If, precedence: CONDITIONAL)
      defnud("QUEUE", Parselet::Queue, precedence: ZERO)
      defnud("WHILE", Parselet::While, precedence: CONDITIONAL)
      defnud("UNTIL", Parselet::Until, precedence: CONDITIONAL)
      defnud("ENSURE", Parselet::Ensure, precedence: ZERO)
      defnud("SYMBOL", Parselet::Symbol)
      defnud("NUMBER", Parselet::Number)
      defnud("STRING", Parselet::String)
      defnud("REGEX", Parselet::Regex)
      defnud("|", Parselet::Spread)
      defnud("(", Parselet::Group)
      defnud("{", Parselet::Block)
      defnud("[", Parselet::Vector)
      defnud("_", Parselet::UPop)
      defnud("&_", Parselet::URef)

      # Infixes (LEDs):
      defled("=", Parselet::Assign, precedence: ASSIGNMENT)
      defled("+=", "-=", "*=", "/=", "~=",
        common: Parselet::BinaryAssign,
        precedence: ASSIGNMENT)
      defled("?", Parselet::IntoBool, precedence: ASSIGNMENT)
      defled("IS", "IN", ">", "<", ">=", "<=", precedence: IDENTITY)
      defled("+", "-", "~", precedence: ADDITION)
      defled("*", "/", "X", precedence: PRODUCT)
      defled("++", Parselet::ReturnIncrement, precedence: POSTFIX)
      defled("--", Parselet::ReturnDecrement, precedence: POSTFIX)
      defled("(", Parselet::Call, precedence: CALL)
      defled(".", Parselet::AccessField, precedence: FIELD)

      # Statements:
      defstmt("FUN", Parselet::Fun)

      ###
      self
    end

    def self.from(filename : String, source : String)
      new(filename, source).register.start
    end
  end
end
