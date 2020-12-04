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
      /[1-9][0-9]*|0/
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
  private KEYWORDS   = ["is", "fun", "else"]

  alias Token = { type: String, raw: String, line: Int32 }

  class Parser
    @tok : Token = { type: "BOL", raw: "beginning-of-line", line: 1 }

    def initialize(@file : String, @src : String)
      @buf = ""
      @pos = 0
      @led = {} of String => Parselet::Led
      @nud = {} of String => Parselet::Nud
      @stmt = {} of String => Parselet::Nud
      @line = 1
      @tok = _accept
    end

    def die(message : String)
      raise ParseError.new(@tok, @file, message)
    end

    private def _match(pattern : Regex) : Bool?
      if pattern =~ @src[@pos..]
        @pos += $0.size
        @buf = $0
        return true
      end
    end

    private macro _token(type)
      { type: {{type}}, raw: @buf, line: @line }
    end

    private def _accept
      loop do
        return case when _match(RX_IGNORE)
          next @line += @buf.count("\n")
        when _match(RX_SPECIAL)
          _token(@buf.upcase)
        when _match(RX_SYMBOL)
          _token(KEYWORDS.includes?(@buf) ? @buf.upcase : "SYMBOL")
        when _match(RX_NUMBER)
          _token("NUMBER")
        when _match(RX_STRING)
          _token("STRING")
        when @pos == @src.size
          _token("EOF")
        else
          raise ParseError.new(@src[@pos].to_s, @line, @file, "malformed input")
        end
      end
    end

    private def _precedence?
      # Symbol `x` is an infix if met in an infix position.
      # Mangle the token so it is.
      if @tok[:type] == "SYMBOL" && @tok[:raw] == "x"
        @tok = { type: "X", raw: "x", line: @tok[:line] }
      end

      @led.fetch(@tok[:type]) { return 0 }.precedence
    end

    def consume
      @tok, _ = _accept, @tok
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

    def followed_by(type : String, unit : ->Quote = ->infix)
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

    def infix(level = 0) : Quote
      left = prefix
      while level < _precedence?
        operator = consume
        left = @led
          .[(operator[:type])]
          .parse(self, QTag.new(@file, @line), left, operator)
      end
      return left
    end

    def stmt : Quote
      if parselet = @stmt.fetch(@tok[:type], false)
        parselet
          .as(Parselet::Nud)
          .parse(self, QTag.new(@file, @line), consume)
      else
        expr = infix; expect(";", "EOF"); expr
      end
    end

    def start : Quotes
      repeat("EOF", unit: ->stmt)
    end

    private macro defnud(type, *tail, storage = @nud, precedence = 0)
      {% unless tail.first.is_a?(StringLiteral) %}
        {{storage}}[{{type}}] = {{tail.first}}.new
      {% else %}
        {% for prefix in [type] + tail %}
          {{storage}}[{{prefix}}] = Parselet::Unary.new({{precedence}})
        {% end %}
      {% end %}
    end

    private macro defled(type, *tail, precedence = 0)
      {% unless tail.first.is_a?(StringLiteral) || !tail.first %}
        @led[{{type}}] = {{tail.first}}.new({{precedence}})
      {% else %}
        {% for infix in [type] + tail %}
          @led[{{infix}}] = Parselet::Binary.new({{precedence}})
        {% end %}
      {% end %}
    end

    private macro defstmt(type, *tail)
      defnud({{type}}, {{*tail}}, storage: @stmt)
    end

    def register
      # XXX TODO: tidy up precedences (mb into Precedence)
      # Prefixes (NUDs):
      defnud("+", "-", "~", precedence: 8)
      defnud("SYMBOL", Parselet::Symbol)
      defnud("NUMBER", Parselet::Number)
      defnud("STRING", Parselet::String)
      defnud("|", Parselet::Spread)
      defnud("(", Parselet::Group)
      defnud("[", Parselet::Vector)
      # Infixes (LUDs):
      defled("=", Parselet::Assign, precedence: 1)
      defled("?", Parselet::IntoBool, precedence: 1)
      defled("=>", Parselet::InlineWhen, precedence: 2)
      defled("IS", ">", "<", ">=", "<=", precedence: 3)
      defled("+", "-", "~", precedence: 4)
      defled("*", "/", "X", precedence: 5)
      defled("(", Parselet::Call, precedence: 10)
      defled("++", Parselet::RetInc, precedence: 7)
      defled("--", Parselet::RetDec, precedence: 7)
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
