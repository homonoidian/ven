module Ven
  # Returns the regex pattern for token *name*, which can be:
  #   * `:SYMBOL`
  #   * `:STRING`
  #   * `:NUMBER`
  #   * `:SPECIAL`
  #   * `:IGNORE`.
  macro regex_for(name)
    {% if name == :SYMBOL %}
      # `&_` and `_` are here as they should be handled as
      # if they were keywords
      /([_a-zA-Z](\-?\w)+|[a-zA-Z])[?!]?|&?_/
    {% elsif name == :STRING %}
      /"([^\n"\\]|\\[ntr\\"])*"/
    {% elsif name == :REGEX %}
      /`([^\\`]|\\.)*`/
    {% elsif name == :NUMBER %}
      /\d*\.\d+|[1-9][\d_]*|0/
    {% elsif name == :SPECIAL %}
      /-[->]|\+\+|=>|[-+*\/~<>]=|[-'<>~+*\/()[\]{},:;=?.|]/
    {% elsif name == :IGNORE %}
      /([ \n\r\t]+|#[^\n]*)/
    {% else %}
      {{ raise "[critical]: no pattern for #{name}" }}
    {% end %}
  end

  # Compile these so there is no regex compilation performance
  # loss each lexical pass.
  private RX_SYMBOL  = /^#{regex_for(:SYMBOL)}/
  private RX_STRING  = /^#{regex_for(:STRING)}/
  private RX_REGEX   = /^#{regex_for(:REGEX)}/
  private RX_NUMBER  = /^#{regex_for(:NUMBER)}/
  private RX_IGNORE  = /^#{regex_for(:IGNORE)}/
  private RX_SPECIAL = /^#{regex_for(:SPECIAL)}/

  # A token is a tagged lexeme. A lexeme is an excerpt from
  # the source code. The patterns above explain how to extract
  # these excerpts.
  alias Token = {type: String, lexeme: String, line: UInt32}

  # The levels of LED precedence in ascending order (lowest
  # to highest.)
  enum Precedence : UInt8
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

  # A reader based on Pratt's parsing algorithm.
  class Reader
    include Component

    # A list of keywords protected by the reader.
    KEYWORDS = %w(_ &_ nud not is in if else fun given loop queue ensure)

    getter token = {type: "START", lexeme: "<start>", line: 1_u32}
    property keywords, world

    def initialize
      @keywords = KEYWORDS

      @led = {} of String => Parselet::Led
      @nud = {} of String => Parselet::Nud
      @stmt = {} of String => Parselet::Nud
      prepare

      @pos = uninitialized Int32
      @src = uninitialized String
      @file = uninitialized String
      @line = uninitialized UInt32
      @world = uninitialized World
      reset
    end

    # Resets
    def reset(@file = "<unknown>", @src = "")
      @pos = 0
      @line = 1_u32

      # Initializes with the first token:
      word

      self
    end

    # Given the explanation *message*, dies of ParseError.
    def die(message : String)
      raise ParseError.new(@token, @file, message)
    end

    # Makes a Token tuple given a *type* and a *lexeme*.
    private macro token(type, lexeme)
      { type: {{type}}, lexeme: {{lexeme}}, line: @line }
    end

    # Matches the offsEt source against the *pattern*. Increments
    # the offset by the match's length if successful.
    private macro match(pattern)
      @pos += $0.size if @src[@pos..] =~ {{pattern}}
    end

    # Consumes a fresh word and returns the former word.
    def word
      fresh =
        loop do
          break case
          when match(RX_IGNORE)
            next @line += $0.count("\n").to_u32
          when match(RX_SPECIAL)
            token($0.upcase, $0)
          when match(RX_SYMBOL)
            token(KEYWORDS.includes?($0) ? $0.upcase : "SYMBOL", $0)
          when match(RX_NUMBER)
            token("NUMBER", $0)
          when match(RX_STRING)
            token("STRING", $0)
          when match(RX_REGEX)
            token("REGEX", $0)
          when @pos == @src.size
            token("EOF", "end-of-input")
          else
            raise ParseError.new(@src[@pos].to_s, @line, @file, "malformed input")
          end
        end

      @token, _ = fresh, @token
    end

    # Reads a word if the type of the current word is *restriction*.
    def word(restriction : String)
      word if @token[:type] == restriction
    end

    # Reads a word if one of the *restrictions* matches the
    # current word's type. Dies of parse error otherwise.
    def expect(*restrictions : String)
      return word if restrictions.includes?(@token[:type])

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

      until stop && word(stop)
        result << unit.call

        if stop && sep
          word(sep) ? next : break expect(stop, sep)
        elsif sep && !word(sep)
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
      @led[@token[:type]]?.try(&.precedence) || 0
    end

    # Parses a led expression with precedence *level*.
    def led(level = Precedence::ZERO.value) : Quote
      left = @nud
        .fetch(token[:type]) { die("not a nud: '#{token[:type]}'") }
        .parse(self, tag?, word)

      # 'x' is a symbol by default; But when used in this very
      # position (after a nud), it's an operator. E.g.:
      #   x x x
      #   ^     left
      #     ^   <operator>
      #       ^ <right>
      @token = token("X", "x") if @token[:lexeme] == "x"

      while level < precedence?
        left = @led[(@token[:type])].parse(self, tag?, left, word)
      end

      left
    end

    # Parses a statament. *trailer* is a word that, in certain
    # cases, functions like a semicolon (e.g., EOF, '}').
    # *detrail* determines whether or not to consume the trailer.
    # NOTE: only leds can be separated by semicolon.
    def statement(trail = "EOF") : Quote
      semi = true

      if stmt = @stmt[@token[:type]]?
        this = stmt.parse(self, tag?, word)
        # Check whether this statement wants a semicolon
        semi = stmt.semicolon?
      else
        this = led
      end

      if !word(";") && semi && token[:type] != trail
        die("neither ';' nor #{trail} weren't found to end the statement")
      end

      this
    end

    # Performs a module-level parse (zero or more statements
    # followed by EOF).
    def module : Quotes
      repeat("EOF", unit: -> { statement })
    end

    # Returns an array of nuds that are of `.class` *only*.
    # If given no *only*, or *only* is nil, returns all nuds.
    def nud?(only pick : (Parselet::Nud.class)? = nil)
      @nud.reject { |_, nud| pick.nil? ? false : nud.class != pick }
    end

    # Returns an array of leds that are of `.class` *only*.
    # If given no *only*, or *only* is nil, returns all leds.
    def led?(only pick : (Parselet::Led.class)? = nil)
      @led.reject { |_, led| pick.nil? ? false : led.class != pick }
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
      defnud("+", "-", "~", "NOT")
      defnud("'", Parselet::PQuote, precedence: ZERO)
      defnud("IF", Parselet::PIf, precedence: CONDITIONAL)
      defnud("NUD", Parselet::PNud, precedence: ZERO)
      defnud("QUEUE", Parselet::PQueue, precedence: ZERO)
      defnud("ENSURE", Parselet::PEnsure, precedence: ZERO)
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
      defled("=", Parselet::PAssign, precedence: ASSIGNMENT)
      defled("+=", "-=", "*=", "/=", "~=",
        common: Parselet::PBinaryAssign,
        precedence: ASSIGNMENT)
      defled("?", Parselet::PIntoBool, precedence: ASSIGNMENT)
      defled("IS", "IN", ">", "<", ">=", "<=", precedence: IDENTITY)
      defled("+", "-", "~", precedence: ADDITION)
      defled("*", "/", "X", precedence: PRODUCT)
      defled("++", Parselet::PReturnIncrement, precedence: POSTFIX)
      defled("--", Parselet::PReturnDecrement, precedence: POSTFIX)
      defled("(", Parselet::PCall, precedence: CALL)
      defled(".", Parselet::PAccessField, precedence: FIELD)

      # Statements:
      defstmt("FUN", Parselet::PFun)
      defstmt("LOOP", Parselet::PLoop)

      self
    end

    # Reads the *source* under the *filename*.
    # ```
    #   Reader.new.read("<sample>", "ensure 2 + 2 is 4").first.to_s
    #   # => "(QEnsure (QBinary is (QBinary + (QNumber 2) (QNumber 2)) (QNumber 4)))"
    # ```
    def read(filename : String, source : String)
      reset(filename, source).module
    end
  end
end
