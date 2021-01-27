module Ven
  # Return the regex pattern for token *name*. *name* can be:
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
      /--|\+\+|=>|[-+*\/~<>]=|[-<>~+*\/()[\]{},:;=?.|]/
    {% elsif name == :IGNORE %}
      /([ \n\r\t]+|#[^\n]*)/
    {% else %}
      {{ raise "[critical]: no pattern for #{name}" }}
    {% end %}
  end

  # Compile these so there is no compilation overhead each
  # lexical pass.
  private RX_SYMBOL  = /^#{regex_for(:SYMBOL)}/
  private RX_STRING  = /^#{regex_for(:STRING)}/
  private RX_REGEX   = /^#{regex_for(:REGEX)}/
  private RX_NUMBER  = /^#{regex_for(:NUMBER)}/
  private RX_IGNORE  = /^#{regex_for(:IGNORE)}/
  private RX_SPECIAL = /^#{regex_for(:SPECIAL)}/

  # A hard-coded list of keywords. It cannot be overridden
  # nor accessed in any way ouside this Parser.
  private KEYWORDS = %w(_ &_ not is in if else fun given until while queue ensure)

  # A token is the smallest meaningful unit of source code.
  alias Token = {type: String, lexeme: String, line: UInt32}

  # All available levels of precedence.
  # NOTE: order matters; ascends (lowest precedence to highest precedence).
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

    getter token = {type: "START", lexeme: "<start>", line: 1_u32}

    def initialize(@file : String, @src : String)
      @pos = 0
      @line = 1_u32

      @led = {} of String => Parselet::Led
      @nud = {} of String => Parselet::Nud
      @stmt = {} of String => Parselet::Nud

      word
    end

    # Given the explanation *message*, die of ParseError.
    def die(message : String)
      raise ParseError.new(@token, @file, message)
    end

    # Make a token out of *type* and *lexeme*, them being correspondingly
    # Token's `type` and `lexeme` fields.
    private macro token(type, lexeme)
      { type: {{type}}, lexeme: {{lexeme}}, line: @line }
    end

    # Match the offset [adverb] source against the *pattern*.
    # Increment the offset if successful.
    private macro match(pattern)
      @pos += $0.size if @src[@pos..] =~ {{pattern}}
    end

    # Read a fresh word and return the former word. Store the
    # fresh word in `@token`.
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

    # Compare the `@token`'s type with *restrict*. Do not
    # read the word if this comparison yields false.
    def word(restrict : String)
      word if @token[:type] == restrict
    end

    # Compare the `@token`'s type with given *restrictions*;
    # If the comparison is true, read a word. Die of expectation
    # error otherwise.
    def expect(*restrictions : String)
      return word if restrictions.includes?(@token[:type])

      die("expected #{restrictions.map(&.dump).join(", ")}")
    end

    # Expect *type* after a call to *unit*.
    def before(type : String, unit : -> T = ->led) forall T
      value = unit.call; expect(type); value
    end

    # Repeatedly call *unit* and return an array of results
    # of each of these calls. Expect one *sep* to follow each
    # *unit* call. If found anything else, expect it to be *stop*
    # and terminate (or, if given no *stop*, just terminate).
    # NOTE: *stop* or *sep*, and *unit* may be omitted; *unit*
    # defaults to a `led`. What comes of omitting *stop* or
    # *sep* is pretty obvious.
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

    # Generate a new QTag.
    private macro tag?
      QTag.new(@file, @line)
    end

    # Get the precedence of the `@token`. Return 0 if it has
    # no precedence,
    private macro precedence?
      @led[@token[:type]]?.try(&.precedence) || 0
    end

    # Parse a led expression with precedence *level*. This
    # method is, no doubt, the most important, and also the
    # most elegant (hopefully), in the reader.
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

    # Parse a statament. *trailer* is the word that allows no
    # semicolon before it. *detrail* determines whether or not
    # to consume this trailer, if found one.
    # NOTE: only leds can be separated by semicolon.
    def statement(trailer = "EOF", detrail = true) : Quote
      if it = @stmt[@token[:type]]?
        return it.parse(self, tag?, word)
      end

      this = led

      # Unless followed by a semicolon, or *detrail* is enabled
      # and *trailer* is consumed, or *trailer* is found
      unless word(";") || detrail && word(trailer) || @token[:type] == trailer
        expect(";", trailer)
      end

      this
    end

    # Perform a module-level parse (zero or more statements
    # followed by EOF).
    def module : Quotes
      repeat("EOF", unit: ->statement)
    end

    # Return an array of nuds that are of `.class` *only*. If
    # given no *only*, return all nuds.
    def nud?(only pick : (Parselet::Nud.class)? = nil)
      @nud.reject { |_, nud| pick.nil? ? false : nud.class != pick }
    end

    # Return an array of leds that are of `.class` *only*. If
    # given no *only*, return all leds.
    def led?(only pick : (Parselet::Led.class)? = nil)
      @led.reject { |_, led| pick.nil? ? false : led.class != pick }
    end

    # Store a nud in *storage* under the key *type*. The nud
    # with precedence *precedence* may be provided in *tail*;
    # alternatively, multiple String literals can be given
    # to generate Unary parselets under the same *precedence*.
    private macro defnud(type, *tail, storage = @nud, precedence = PREFIX)
      {% unless tail.first.is_a?(StringLiteral) %}
        {{storage}}[{{type}}] = {{tail.first}}.new
      {% else %}
        {% for prefix in [type] + tail %}
          {{storage}}[{{prefix}}] = Parselet::PUnary.new(Precedence::{{precedence}}.value)
        {% end %}
      {% end %}
    end

    # Store a led in `@leds` under the key *type*. The led
    # with precedence *precedence* may be provided in *tail*;
    # alternatively, multiple String literals can be given
    # to generate *common* parselets under the same *precedence*.
    private macro defled(type, *tail, common = Parselet::PBinary, precedence = ZERO)
      {% if !tail.first.is_a?(StringLiteral) && tail.first %}
        @led[{{type}}] = {{tail.first}}.new(Precedence::{{precedence}}.value)
      {% else %}
        {% for infix in [type] + tail %}
          @led[{{infix}}] = {{common}}.new(Precedence::{{precedence}}.value)
        {% end %}
      {% end %}
    end

    private macro defstmt(type, *tail)
      defnud({{type}}, {{*tail}}, storage: @stmt)
    end

    def prepare
      # Prefixes (NUDs):
      defnud("+", "-", "~", "NOT")
      defnud("IF", Parselet::PIf, precedence: CONDITIONAL)
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
      defstmt("WHILE", Parselet::PWhile)
      defstmt("UNTIL", Parselet::PUntil)

      self
    end
  end

  # Initialize a Reader and read the *source*.
  #
  # ```
  # Ven.read("<sample>", "ensure 2 + 2 is 4").first.to_s
  # # ==> "(QEnsure (QBinary is (QBinary + (QNumber 2) (QNumber 2)) (QNumber 4)))"
  # ```
  def self.read(filename : String, source : String)
    Reader.new(filename, source).prepare.module
  end
end
