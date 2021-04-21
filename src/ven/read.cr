module Ven
  # Returns the regex pattern for word *name*. *name* may be:
  #
  #   * `:SYMBOL`
  #   * `:STRING`
  #   * `:REGEX`
  #   * `:NUMBER`
  #   * `:SPECIAL`
  #   * `:IGNORE`.
  macro regex_for(name)
    {% if name == :SYMBOL %}
      # `&_` and `_` are here as they should be handled as
      # if they were keywords
      /([$_a-zA-Z](\-?\w)+|[a-zA-Z])[?!]?|&?_|\$/
    {% elsif name == :STRING %}
      /"([^\n"\\]|\\[ntr\\"])*"/
    {% elsif name == :REGEX %}
      /`([^\\`]|\\.)*`/
    {% elsif name == :NUMBER %}
      /(\d[\d_]*)?\.[\d_]+|[1-9][\d_]*|0/
    {% elsif name == :SPECIAL %}
      /-[->]|\+\+|=>|[-+*\/~<>&:]=|[-'<>~+\/()[\]{},:;=?.|#&*]/
    {% elsif name == :IGNORE %}
      /[ \n\r\t]+|#([ \t][^\n]*|\n+)/
    {% else %}
      {{ raise "[critical]: no pattern for #{name}" }}
    {% end %}
  end

  # A word is a tagged lexeme. A lexeme is an excerpt from
  # the source code.
  alias Word = {type: String, lexeme: String, line: UInt32}

  # The levels of LED precedence in ascending order (lowest
  # to highest.)
  enum Precedence : UInt8
    ZERO
    ASSIGNMENT
    CONVERT
    JUNCTION
    IDENTITY
    RANGE
    ADDITION
    PRODUCT
    POSTFIX
    PREFIX
    CALL
    FIELD
  end

  # A reader based on Pratt's parsing algorithm.
  class Reader
    include Suite

    RX_REGEX   = /^(#{Ven.regex_for(:REGEX)})/
    RX_SYMBOL  = /^(#{Ven.regex_for(:SYMBOL)})/
    RX_STRING  = /^(#{Ven.regex_for(:STRING)})/
    RX_NUMBER  = /^(#{Ven.regex_for(:NUMBER)})/
    RX_IGNORE  = /^(#{Ven.regex_for(:IGNORE)})/
    RX_SPECIAL = /^(#{Ven.regex_for(:SPECIAL)})/

    # A list of keywords protected by the reader.
    KEYWORDS = %w(
      _ &_ nud not is in if else fun
      given loop next queue ensure expose
      distinct box and or return dies to)

    getter word = {type: "START", lexeme: "<start>", line: 1_u32}

    property leads
    property keywords

    property nud
    property led

    def initialize
      @leads = {} of String => Regex
      @keywords = KEYWORDS

      @led = {} of String => Parselet::Led
      @nud = {} of String => Parselet::Nud
      @stmt = {} of String => Parselet::Nud
      prepare

      @pos = uninitialized Int32
      @src = uninitialized String
      @file = uninitialized String
      @line = uninitialized UInt32
      reset
    end

    # Resets this reader.
    def reset(@file = "<unknown>", @src = "")
      @pos = 0
      @line = 1_u32

      # Reads the first word:
      word!

      self
    end

    # Given the explanation *message*, dies of ParseError.
    def die(message : String)
      raise ReadError.new(@word, @file, message)
    end

    # Makes a Word tuple given a *type* and a *lexeme*.
    private macro word(type, lexeme)
      { type: {{type}}, lexeme: {{lexeme}}, line: @line }
    end

    # Matches the offsEt source against the *pattern*. Increments
    # the offset by the match's length if successful.
    private macro match(pattern)
      @pos += $0.size if @src[@pos..] =~ {{pattern}}
    end

    # Returns the current word and consumes the next one.
    def word!
      fresh =
        loop do
          break case
          when match(RX_IGNORE)
            next @line += $0.count("\n").to_u32
          when match(RX_SYMBOL)
            if KEYWORDS.includes?($0)
              word($0.upcase, $0)
            elsif $0.size > 1 && $0.starts_with?("$")
              word("EXPASYM", $0)
            else
              word("SYMBOL", $0)
            end
          when match(RX_NUMBER)
            word("NUMBER", $0)
          when match(RX_STRING)
            word("STRING", $0)
          when match(RX_REGEX)
            word("REGEX", $0)
          when pair = @leads.find { |_, lead| match(lead) }
            word(pair[0], $0)
          when match(RX_SPECIAL)
            word($0.upcase, $0)
          when @pos == @src.size
            word("EOF", "end-of-input")
          else
            raise ReadError.new(@src[@pos].to_s, @line, @file, "malformed input")
          end
        end

      @word, _ = fresh, @word
    end

    # Reads a word if the type of the current word is *restriction*.
    def word!(restriction : String)
      word! if @word[:type] == restriction
    end

    # Reads a word if one of the *restrictions* matches the
    # current word's type. Dies of parse error otherwise.
    def expect(*restrictions : String)
      return word! if restrictions.includes?(@word[:type])

      die("expected #{restrictions.map(&.dump).join(", ")}")
    end

    # Expects *type* after calling *unit*.
    def before(type : String, unit : -> T = ->led) forall T
      value = unit.call; expect(type); value
    end

    # Calls *unit* repeatedly, remembering what each call
    # results in, and returns an Array of the results. Expects
    # a *sep* after each unit. Terminates at *stop*.
    # NOTE: either *stop* or *sep*, and *unit* may be omitted;
    # *unit* defaults to a `led`.
    def repeat(stop : String? = nil, sep : String? = nil, unit : -> T = ->led) forall T
      unless stop || sep
        raise "[critical]: stop or sep or stop and sep; none given"
      end

      result = [] of T

      until stop && word!(stop)
        result << unit.call

        if stop && sep
          word!(sep) ? next : break expect(stop, sep)
        elsif sep && !word!(sep)
          break
        end
      end

      result
    end

    # Generates a new QTag.
    private macro tag?
      QTag.new(@file, @line)
    end

    # Returns the precedence of the current word. Returns 0
    # if it has no precedence.
    private macro precedence?
      @led[(@word[:type])]?.try(&.precedence) || 0
    end

    # Parses a led expression with precedence *level*.
    def led(level = Precedence::ZERO.value) : Quote
      die("strange expression instead of a nud") unless is_nud?

      left = @nud[(@word[:type])].parse(self, tag?, word!)

      if @word[:lexeme] == "x"
        @word = word("X", "x")
      end

      while level < precedence?
        left = @led[(@word[:type])].parse(self, tag?, left, word!)
      end

      left
    end

    # Returns whether this token is a valid statement delimiter.
    def eoi?
      word[:type].in?("EOF", "}", ";")
    end

    # Parses a single statament.
    def statement : Quote
      semi = true

      if stmt = @stmt[(@word[:type])]?
        this = stmt.parse(self, tag?, word!)
        # Check whether this statement wants a semicolon
        semi = stmt.semicolon?
      else
        this = led
      end

      if !word!(";") && semi && !eoi?
        die("neither ';' nor end-of-input were found to end the statement")
      end

      this
    end

    # Performs a module-level parse (zero or more statements
    # followed by EOF). Each statement is yielded to *block*.
    def module(&block)
      until word!("EOF")
        last = yield statement
      end

      last
    end

    # Returns whether this word is a nud. *pick* may be provided
    # to check only certain parselet classes.
    def is_nud?(only pick : Parselet::Nud.class)
      @nud.each do |k, v|
        return true if k == @word[:type] && v.class == pick
      end
    end

    # :ditto:
    def is_nud?
      @nud.has_key?(@word[:type])
    end

    # Returns whether this word is a led. *pick* may be provided
    # to check only certain parselet classes.
    def is_led?(only pick : Parselet::Led.class)
      @led.each do |k, v|
        return true if k == @word[:type] && v.class == pick
      end
    end

    # :ditto:
    def is_led?
      @led.has_key?(@word[:type])
    end

    # Returns whether this word is a statement.
    def is_stmt?
      @stmt.has_key?(@word[:type])
    end

    # Stores a nud in a hash *storage*, under the key *type*.
    # A nud with precedence *precedence* may be provided in
    # *tail*; alternatively, multiple String literals can be given
    # to generate Unary parselets with the same *precedence*.
    private macro defnud(type, *tail, storage = @nud, precedence = PREFIX)
      {% unless tail.first.is_a?(StringLiteral) %}
        {{storage}}[{{type}}] = {{tail.first}}.new
      {% else %}
        {% for prefix in [type] + tail %}
          {{storage}}[{{prefix}}] = Parselet::PUnary.new(Precedence::{{precedence}}.value)
        {% end %}
      {% end %}
    end

    # Stores a led in `@leds`, under the key *type*. A led
    # with precedence *precedence* may be provided in *tail*;
    # alternatively, multiple String literals can be given
    # to generate *common* parselets with the same *precedence*.
    private macro defled(type, *tail, common = Parselet::PBinary, precedence = ZERO)
      {% if !tail.first.is_a?(StringLiteral) && tail.first %}
        @led[{{type}}] = {{tail.first}}.new(Precedence::{{precedence}}.value)
      {% else %}
        {% for infix in [type] + tail %}
          @led[{{infix}}] = {{common}}.new(Precedence::{{precedence}}.value)
        {% end %}
      {% end %}
    end

    # Stores a statement in `@stmt`, under the key *type*.
    # *tail* is interpreted by `defnud`.
    private macro defstmt(type, *tail)
      defnud({{type}}, {{*tail}}, storage: @stmt)
    end

    # Initializes this reader so it is capable of reading
    # base Ven.
    def prepare
      # Prefixes (NUDs):

      defnud("+", "-", "~", "&", "#", "NOT")

      defnud("'", Parselet::PQuote)
      defnud("EXPASYM", Parselet::PExpansionSymbol)
      defnud("IF", Parselet::PIf)
      defnud("NEXT", Parselet::PNext)
      defnud("RETURN", Parselet::PReturnExpression)
      defnud("QUEUE", Parselet::PQueue)
      defnud("ENSURE", Parselet::PEnsure)
      defnud("*", Parselet::PSymbol)
      defnud("SYMBOL", Parselet::PSymbol)
      defnud("NUMBER", Parselet::PNumber)
      defnud("STRING", Parselet::PString)
      defnud("REGEX", Parselet::PRegex)
      defnud("|", Parselet::PSpread)
      defnud("(", Parselet::PGroup)
      defnud("{", Parselet::PBlock)
      defnud("[", Parselet::PVector)
      defnud("_", Parselet::PUPop)
      defnud("&_", Parselet::PURef)

      # Infixes (LEDs):

      defled("=", ":=",
        common: Parselet::PAssign,
        precedence: ASSIGNMENT)

      defled("+=", "-=", "*=", "/=", "~=", "&=",
        common: Parselet::PBinaryAssign,
        precedence: ASSIGNMENT)

      defled("DIES", Parselet::PDies, precedence: CONVERT)
      defled("AND", "OR", precedence: JUNCTION)
      defled("?", Parselet::PIntoBool, precedence: IDENTITY)
      defled("IS", "IN", ">", "<", ">=", "<=", precedence: IDENTITY)
      defled("TO", precedence: RANGE)
      defled("+", "-", "~", "&", precedence: ADDITION)
      defled("*", "/", "X", precedence: PRODUCT)
      defled("++", Parselet::PReturnIncrement, precedence: POSTFIX)
      defled("--", Parselet::PReturnDecrement, precedence: POSTFIX)
      defled("(", Parselet::PCall, precedence: CALL)
      defled(".", Parselet::PAccessField, precedence: FIELD)

      # Statements:

      defstmt("NUD", Parselet::PDefineNud)
      defstmt("FUN", Parselet::PFun)
      defstmt("BOX", Parselet::PBox)
      defstmt("LOOP", Parselet::PLoop)
      defstmt("EXPOSE", Parselet::PExpose)
      defstmt("DISTINCT", Parselet::PDistinct)
      defstmt("RETURN", Parselet::PReturnStatement)

      self
    end

    def to_s(io)
      io << "<reader for '#{@file}'>"
    end

    # Reads the *source* under the *filename*.
    def read(filename : String, source : String, &block : Quote -> _)
      reset(filename, source).module do |quote|
        yield quote
      end
    end
  end
end
