module Ven
  # A word is a tagged lexeme. A lexeme is a verbatim citation
  # of the source code.
  alias Word = { type: String, lexeme: String, line: Int32 }

  # Returns the regex pattern for word type *type*. *type*
  # can be:
  #
  #   * `:SYMBOL`
  #   * `:STRING`
  #   * `:REGEX`
  #   * `:NUMBER`
  #   * `:SPECIAL`
  #   * `:IGNORE`.
  #
  # Raises if there is no such word.
  macro regex_for(type)
    {% if type == :SYMBOL %}
      # `&_` and `_` should be handled as if they were keywords.
      /(?:[$_a-zA-Z](?:\-?\w)+|[a-zA-Z])[?!]?|&?_|\$/
    {% elsif type == :STRING %}
      /"(?:[^\n"\\]|\\[ntr\\"])*"/
    {% elsif type == :REGEX %}
      /`(?:[^\\`]|\\.)*`/
    {% elsif type == :NUMBER %}
      /(?:\d(?:_?\d)*)?\.(?:_?\d)+|[1-9](?:_?\d)*|0/
    {% elsif type == :SPECIAL %}
      /-[->]|\+\+|=>|[-+*\/~<>&:]=|[-'<>~+\/()[\]{},:;=?.|#&*]/
    {% elsif type == :IGNORE %}
      /[ \n\r\t]+|#(?:[ \t][^\n]*|\n+)/
    {% else %}
      {{ raise "no word type #{type}" }}
    {% end %}
  end

  # The levels of led precedence in ascending order (lower is
  # looser, higher is tighter).
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

  # A reader capable of parsing Ven.
  #
  # Basic usage (see `Reader.read` and `program`):
  #
  # ```
  # puts Ven::Reader.read("2 + 2")
  # ```
  class Reader
    include Suite

    RX_REGEX   = /^(?:#{Ven.regex_for(:REGEX)})/
    RX_SYMBOL  = /^(?:#{Ven.regex_for(:SYMBOL)})/
    RX_STRING  = /^(?:#{Ven.regex_for(:STRING)})/
    RX_NUMBER  = /^(?:#{Ven.regex_for(:NUMBER)})/
    RX_IGNORE  = /^(?:#{Ven.regex_for(:IGNORE)})/
    RX_SPECIAL = /^(?:#{Ven.regex_for(:SPECIAL)})/

    # Built-in keywords.
    KEYWORDS = %w(
      _ &_ nud not is in if else fun
      given loop next queue ensure expose
      distinct box and or return dies to)

    # Returns the current word.
    getter word = { type: "START", lexeme: "<start>", line: 1 }
    # Returns this reader's context.
    getter context

    # Current line number.
    @lineno = 1
    # Current offset.
    @offset = 0

    # Creates a new reader.
    #
    # *source* (the only required argument) is for the source
    # code, *file* is for the filename, and *context* is for
    # the reader context.
    #
    # NOTE: instances of Reader should be disposed after the
    # first use.
    #
    # ```
    # Reader.new("1 + 1")
    # ```
    def initialize(@source : String, @file : String = "untitled", @context = Context::Reader.new)
      # Read the first word:
      word!

      @led = {} of String => Parselet::Led
      @nud = {} of String => Parselet::Nud
      @stmt = {} of String => Parselet::Nud
      prepare
    end

    # Given an explanation message, *message*, dies of `ReadError`.
    def die(message : String)
      raise ReadError.new(@word, @file, message)
    end

    # Makes a `QTag`.
    private macro tag
      QTag.new(@file, @lineno)
    end

    # Makes a `Word` given a *type* and a *lexeme*.
    private macro word(type, lexeme)
      { type: {{type}}, lexeme: {{lexeme}}, line: @lineno }
    end

    # Returns whether *lexeme* is a keyword.
    #
    # On conflict, built-in keywords (see `KEYWORDS`) take
    # precedence over the user-defined keywords.
    private macro keyword?(lexeme)
      {{lexeme}}.in?(KEYWORDS) || @context.keyword?({{lexeme}})
    end

    # Looks up the nud for word type *type*.
    #
    # Raises if not found.
    private macro nud_for?(type)
      @nud[{{type}}]? || @context.nuds[{{type}}]?
    end

    # Looks up the led for word type *type*.
    #
    # Returns nil if not found.
    private macro led_for?(type)
      @led[{{type}}]?
    end

    # Looks up the nud for word type *type*.
    #
    # Raises if not found.
    private macro nud_for(type)
      nud_for?({{type}}) || raise "nud for '#{{{type}}}' not found"
    end

    # Looks up the led for word type *type*.
    #
    # Raises if not found.
    private macro led_for(type)
      led_for?({{type}}) || raise "led for '#{{{type}}}' not found"
    end

    # Looks up the precedence of the current word (see `Precedence`)
    #
    # Returns `Precedence::ZERO` if it has no precedence.
    private macro precedence
      @led[(@word[:type])]?.try(&.precedence) || Precedence::ZERO
    end

    # Matches offset source against a regex *pattern*. If successful,
    # increments the offset by matches' length.
    private macro match(pattern)
      @offset += $0.size if @source[@offset..] =~ {{pattern}}
    end

    # Returns the current word and consumes the next one.
    def word!
      fresh =
        loop do
          break case
          when match(RX_IGNORE)
            next @lineno += $0.count("\n")
          when match(RX_SYMBOL)
            if keyword?($0)
              word($0.upcase, $0)
            elsif $0.size > 1 && $0.starts_with?("$")
              word("$SYMBOL", $0[1..])
            else
              word("SYMBOL", $0)
            end
          when match(RX_NUMBER)
            word("NUMBER", $0)
          when match(RX_STRING)
            word("STRING", $0)
          when match(RX_REGEX)
            word("REGEX", $0)
          when pair = @context.triggers.find { |_, lead| match(lead) }
            word(pair[0], $0)
          when match(RX_SPECIAL)
            word($0.upcase, $0)
          when @offset == @source.size
            word("EOF", "end-of-input")
          else
            raise ReadError.new(@source[@offset].to_s, @lineno, @file, "malformed input")
          end
        end

      @word, _ = fresh, @word
    end

    # Returns the current word and consumes the next one, but
    # only if the current word is of type *type*. Returns nil
    # otherwise.
    def word!(type : String)
      word! if @word[:type] == type
    end

    # Returns the current word and consumes the next one,
    # but only if the current word is of one of the given
    # *types*. Dies of read error otherwise.
    def expect(*types : String)
      return word! if types.includes?(@word[:type])

      die("expected #{types.map(&.dump).join(", ")}")
    end

    # Expects *type* after calling *unit*. Returns whatever
    # *unit* returns.
    def before(type : String, unit : -> T = ->led) forall T
      value = unit.call; expect(type); value
    end

    # Calls *unit* repeatedly; assembles the results of each
    # call in an Array, and returns that array on termination.
    #
    # Expects *sep* after each call to *unit*. Terminates
    # on *stop*.
    def repeat(stop : String? = nil, sep : String? = nil, unit : -> T = ->led) forall T
      raise "repeat(): got no stop/sep" unless stop || sep

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

    # Reads a led expression with precedence level *level*
    # (see `Precedence`).
    def led(level : Precedence = Precedence::ZERO) : Quote
      die("expected an expression") unless is_nud?

      left = nud_for(@word[:type]).parse!(self, tag, word!)

      # 'x' is special. If met in nud position, it's a symbol;
      # if met in operator position, it's a keyword.
      if @word[:lexeme] == "x"
        @word = word("X", "x")
      end

      while level.value < precedence.value
        left = led_for(@word[:type]).parse(self, tag, left, word!)
      end

      left
    end

    # Returns whether the current word is one of the end-of-input
    # words. Semicolons are optional before end-of-input words.
    def eoi?
      word[:type].in?("EOF", "}", ";")
    end

    # Reads a statement.
    def statement : Quote
      if stmt = @stmt[(@word[:type])]?
        this = stmt.parse!(self, tag, word!)
        semi = stmt.semicolon
      else
        this = led
        semi = true
      end

      if !word!(";") && semi && !eoi?
        die("neither ';' nor end-of-input were found to end the statement")
      end

      this
    end

    # Reads the whole program (i.e., zero or more statements
    # followed by EOF). Each statement is yielded to the block.
    #
    # Returns nothing.
    def program
      until word!("EOF")
        yield statement
      end
    end

    # Reads the whole program into an Array of `Quote`s. Returns
    # that array.
    def program
      quotes = Quotes.new

      until word!("EOF")
        quotes << statement
      end

      quotes
    end

    # Returns whether the current word is a nud of type *pick*.
    def is_nud?(only pick : Parselet::Nud.class) : Bool
      !!nud_for?(@word[:type]).try(&.class.== pick)
    end

    # Returns whether the current word is a nud.
    def is_nud?
      !!nud_for?(@word[:type])
    end

    # Returns whether the current word is a led of type *pick*.
    def is_led?(only pick : Parselet::Led.class) : Bool
      !!led_for?(@word[:type]).try(&.class.== pick)
    end

    # Returns whether the current word is a led.
    def is_led?
      !!led_for?(@word[:type])
    end

    # Returns whether the current word is a statement.
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
          {{storage}}[{{prefix}}] = Parselet::PUnary.new(Precedence::{{precedence}})
        {% end %}
      {% end %}
    end

    # Stores a led in `@leds`, under the key *type*. A led
    # with precedence *precedence* may be provided in *tail*;
    # alternatively, multiple String literals can be given
    # to generate *common* parselets with the same *precedence*.
    private macro defled(type, *tail, common = Parselet::PBinary, precedence = ZERO)
      {% if !tail.first.is_a?(StringLiteral) && tail.first %}
        @led[{{type}}] = {{tail.first}}.new(Precedence::{{precedence}})
      {% else %}
        {% for infix in [type] + tail %}
          @led[{{infix}}] = {{common}}.new(Precedence::{{precedence}})
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

      defnud("$SYMBOL", Parselet::PSymbol)
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
  end
end
