require "./parselet/*"
require "./component/quote"
require "./component/error"

module Ven
  macro regex_for(name)
    {% if name == :SYMBOL %}
      /[_a-zA-Z](\-?\w)*[?!]?/
    {% elsif name == :STRING %}
      /"([^\n"])*"/
    {% elsif name == :NUMBER %}
      /\d*\.\d+|[1-9]\d*|0/
    {% elsif name == :SPECIAL %}
      /--|\+\+|=>|<=|>=|[-<>~+*\/()[\]{},:;=?|]/
    {% elsif name == :IGNORE %}
      /([ \n\r\t]+|#[^\n]*)/
    {% else %}
      {{ raise "no pattern for #{name}" }}
    {% end %}
  end

  private RX_SYMBOL  = /^#{regex_for(:SYMBOL)}/
  private RX_STRING  = /^#{regex_for(:STRING)}/
  private RX_NUMBER  = /^#{regex_for(:NUMBER)}/
  private RX_IGNORE  = /^#{regex_for(:IGNORE)}/
  private RX_SPECIAL = /^#{regex_for(:SPECIAL)}/
  private KEYWORDS   = ["is", "fun", "if", "else"]

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
  end

  class Parser
    @tok : Token = {
      type: "START",
      raw: "start anchor",
      line: 1,
    }

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
        when @pos == @src.size
          token("EOF")
        else
          raise ParseError.new(@src[@pos].to_s, @line, @file, "malformed input")
        end
      end
    end

    private def precedence?
      # Symbol `x` is an infix if met in an infix position.
      # Mangle the token so it is.
      if @tok[:type] == "SYMBOL" && @tok[:raw] == "x"
        @tok = {type: "X", raw: "x", line: @tok[:line]}
      end

      @led.fetch(@tok[:type]) { return 0 }.precedence
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
      if types.includes?(@tok[:type])
        consume
      elsif tys = types.map { |x| "'#{x}'" }
        die("expected #{tys.join(", ")}")
      end.not_nil!
    end

    def before(type : String, unit : -> Quote = ->infix)
      value = unit.call; expect(type); value
    end

    def repeat(stop : String? = nil, sep : String? = nil, unit : -> T = ->infix) forall T
      result = [] of T
      until consume(stop)
        result << unit.call
        if stop && sep
          consume(sep) ? next : break expect(stop, sep)
        elsif sep && !consume(sep)
          break
        elsif consume(stop)
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
        operator = consume
        left = @led
          .[(operator[:type])]
          .parse(self, QTag.new(@file, @line), left, operator)
      end
      return left
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
          # Just to print an 'expected' error:
          expect(";", trail)
        end.as(Quote)
      end
    end

    def start : Quotes
      repeat("EOF", unit: ->statement)
    end

    private macro defnud(type, *tail, storage = @nud, precedence = ZERO)
      {% unless tail.first.is_a?(StringLiteral) %}
        {{storage}}[{{type}}] = {{tail.first}}.new
      {% else %}
        {% for prefix in [type] + tail %}
          {{storage}}[{{prefix}}] = Parselet::Unary.new(Precedence::{{precedence}}.value)
        {% end %}
      {% end %}
    end

    private macro defled(type, *tail, precedence = ZERO)
      {% unless tail.first.is_a?(StringLiteral) || !tail.first %}
        @led[{{type}}] = {{tail.first}}.new(Precedence::{{precedence}}.value)
      {% else %}
        {% for infix in [type] + tail %}
          @led[{{infix}}] = Parselet::Binary.new(Precedence::{{precedence}}.value)
        {% end %}
      {% end %}
    end

    private macro defstmt(type, *tail)
      defnud({{type}}, {{*tail}}, storage: @stmt)
    end

    def register
      # Prefixes (NUDs):
      defnud("+", "-", "~", precedence: PREFIX)
      defnud("IF", Parselet::If, precedence: CONDITIONAL)
      defnud("SYMBOL", Parselet::Symbol)
      defnud("NUMBER", Parselet::Number)
      defnud("STRING", Parselet::String)
      defnud("|", Parselet::Spread)
      defnud("(", Parselet::Group)
      defnud("{", Parselet::Block)
      defnud("[", Parselet::Vector)
      # Infixes (LUDs):
      defled("=", Parselet::Assign, precedence: ASSIGNMENT)
      defled("?", Parselet::IntoBool, precedence: ASSIGNMENT)
      defled("IS", ">", "<", ">=", "<=", precedence: IDENTITY)
      defled("+", "-", "~", precedence: ADDITION)
      defled("*", "/", "X", precedence: PRODUCT)
      defled("(", Parselet::Call, precedence: CALL)
      defled("++", Parselet::RetInc, precedence: POSTFIX)
      defled("--", Parselet::RetDec, precedence: POSTFIX)
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
