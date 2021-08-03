module Ven
  # In terms of Ven, a word is a tagged lexeme.
  struct Word
    # Returns the type of this word. Note that by convention, Word
    # types should be all-uppercase.
    getter type : String
    # Returns the lexeme of this word. A lexeme is a verbatim citation
    # of the source code.
    getter lexeme : String
    # Returns a hash of named captures the regex for this word made.
    getter! matches : Hash(String, String?)

    # Returns the start offset of this word.
    getter begin : Int32
    # Returns the end offset of this word.
    getter end : Int32
    # Returns the line number of the line this word was found on.
    getter line : Int32
    # Returns the visual end column of this word. It points to the
    # character after this word's last character (or 1).
    getter end_column : Int32
    # Returns the visual begin column of this word. It points to
    # the character before this word's first character (or 1).
    getter begin_column : Int32

    def initialize(@type, @lexeme, @line, @begin, @end_column, @matches = nil)
      @end = @begin + @lexeme.size
      # Compute from the end column and lexeme size.
      # puts @lexeme
      # puts @end_column
      @begin_column = @end_column - @lexeme.size
    end

    def to_s(io)
      io << "'" << @type << "' at " << @line << ":" << @begin_column << ".." << @end_column

      @matches.try &.each do |capture, match|
        io << "  " << capture << " = " << match
      end
    end

    # Returns a Word with sane dummy values.
    def self.dummy
      Word.new("DUMMY", "", line: 1, begin: 0, end_column: 1)
    end
  end

  # The type that represents a Ven distinct.
  alias Distinct = Array(String)

  # Returns the regex pattern for word type *type*. *type*
  # can be:
  #
  #   * `:SYMBOL`
  #   * `:STRING`
  #   * `:STRING_ESCAPES`
  #   * `:REGEX`
  #   * `:NUMBER`
  #   * `:SPECIAL`
  #   * `:IGNORE`.
  #
  # Raises at compile-time if *type* is invalid.
  macro regex_for(type)
    {% if type == :SYMBOL %}
      # `&_` and `_` should be handled as if they were keywords.
      /(?:(?:[$_a-zA-Z](?:\-?\w)+|[a-zA-Z])[?!]?|&?_|\$)/
    {% elsif type == :STRING %}
      /"((?:[^\n"\\]|#{Ven.regex_for(:STRING_ESCAPES)})*)"/
    {% elsif type == :STRING_ESCAPES %}
      /\\[$a-z\\"]/
    {% elsif type == :REGEX %}
      /`((?:[^\\`]|\\.)*)`/
    {% elsif type == :NUMBER %}
      /(?:(?:\d(?:_?\d)*)?\.(?:_?\d)+|[1-9](?:_?\d)*|0)/
    {% elsif type == :SPECIAL %}
      /(?:%\{|-[->]|\+\+|=>|[-+*\/~<>&:%]=|[-'<>~+\/()[\]{},:;=?.|#&*%])/
    {% elsif type == :IGNORE %}
      /(?:[ \n\r\t]+|#(?:[ \t][^\n]*|\n+))/
    {% else %}
      {{ raise "regex_for(): invalid type: #{type}" }}
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

  # The Ven reader.
  #
  # This is a vital part of the Ven programming language. Without
  # it, well, Ven would just not have a syntax.
  #
  # Internally, Ven reader is a Pratt parser with parselets on top
  # (see Bob Nystrom). An intricate and powerful combo, in other
  # words, and one that allows, say, read-time evaluation, as well
  # as self-parsing (read macros).
  #
  # **Instances of Reader should be disposed after the first use.**
  class Reader
    include Suite

    RX_REGEX   = Ven.regex_for(:REGEX)
    RX_SYMBOL  = Ven.regex_for(:SYMBOL)
    RX_STRING  = Ven.regex_for(:STRING)
    RX_NUMBER  = Ven.regex_for(:NUMBER)
    RX_IGNORE  = Ven.regex_for(:IGNORE)
    RX_SPECIAL = Ven.regex_for(:SPECIAL)

    # Built-in keywords.
    KEYWORDS = %w(
      _ &_ nud not is in if else fun
      given loop next queue ensure expose
      distinct box and or return dies to
      should from immediate true false)

    # Consensus invalid character word type. Issued exclusively in
    # the verbal mode (see `word!`).
    INVALID_PSEUDOWORD = "__INVALID__"

    # Returns the current word.
    getter word : Word = Word.dummy
    # Returns this reader's context.
    getter context : CxReader

    # Current line number (incremented by one each line).
    #
    # You can change this value if you want to, but only
    # if you know what you're doing.
    property lineno = 1

    # Whether this reader's state is dirty.
    @dirty = false
    # Current column (counts from 1 on).
    @column = 1
    # Current character offset.
    @offset = 0
    # Whether the verbal lexical analysis mode is enabled.
    @verbal = false

    # Makes a new reader.
    #
    # *source*, the source code of your program, is the only
    # required argument.
    #
    # *file* is the name by which this source code will be
    # identified; normally it's filename.
    #
    # *context* is the context for this Reader (see
    # `Context::Reader`).
    #
    # *enquiry* is the Enquiry object used to send/read global
    # signals, properties, configurations et al.
    def initialize(@source : String, @file = "untitled", @context = CxReader.new, @enquiry = Enquiry.new)
      # Read the first word:
      word!

      @led = {} of String => Parselet::Led
      @nud = {} of String => Parselet::Nud
      @stmt = {} of String => Parselet::Nud
      prepare
    end

    # Performs an extremely lightweight initialization routine.
    # Useful for doing *verbal*-only passovers. Raises if given
    # falsey *verbal*.
    def initialize(@source : String, @verbal : Bool, @context = CxReader.new)
      raise "call the other initialize() then" unless @verbal

      @led = uninitialized Hash(String, Parselet::Led)
      @nud = uninitialized Hash(String, Parselet::Nud)
      @stmt = uninitialized Hash(String, Parselet::Nud)
      @file = uninitialized String
      @enquiry = uninitialized Enquiry

      # Read the first word.
      word!
    end

    # Given an explanation message, *message*, dies of `ReadError`.
    def die(message : String)
      raise ReadError.new(@word, @file, message)
    end

    # Makes a `QTag`. Extracts the data about the location from the
    # current word.
    private macro tag
      QTag.new(@file, @word.line, @word.begin_column,
        # I am still not sure about this: should the tag
        # be end_column'ed by the quote, or should the
        # reader do this instead?
        @word.end_column)
    end

    # Makes a `Word` from the given *type* and *lexeme*.
    #
    # *matches* is the optional `MatchData` of the word
    # (see `Word#matches`).
    private macro word(type, lexeme, matches = nil)
      %lexeme = {{lexeme}}
      # We have to compute *begin* for `Word`, as `word` is
      # called after the word is read, and after the *offset*
      # is incremented by word's size.
      Word.new({{type}}, %lexeme, @lineno, @offset - %lexeme.size, @column, {{matches}})
    end

    # Returns whether *lexeme* is a keyword.
    #
    # On conflict, built-in keywords (`KEYWORDS`) take precedence
    # over the user-defined keywords.
    private macro keyword?(lexeme)
      {{lexeme}}.in?(KEYWORDS) || @context.keyword?({{lexeme}})
    end

    # Looks up the nud parselet for word type *type*.
    #
    # Returns nil if not found.
    private macro nud_for?(type)
      @nud[{{type}}]? || @context.nuds[{{type}}]?
    end

    # Looks up the led parselet for word type *type*.
    #
    # Returns nil if not found.
    private macro led_for?(type)
      @led[{{type}}]?
    end

    # Looks up the nud parselet for word type *type*.
    #
    # Raises if not found.
    private macro nud_for(type)
      nud_for?({{type}}) || raise "nud parselet for '#{{{type}}}' not found"
    end

    # Looks up the led parselet for word type *type*.
    #
    # Raises if not found.
    private macro led_for(type)
      led_for?({{type}}) || raise "led parselet for '#{{{type}}}' not found"
    end

    # Looks up the precedence of the current word (see `Precedence`)
    #
    # Returns `Precedence::ZERO` if it has no precedence.
    private macro precedence
      @led[@word.type]?.try(&.precedence) || Precedence::ZERO
    end

    # Matches offset source against a regex *pattern*. If
    # successful, increments the offset by matches' length.
    private macro match(pattern)
      if @source[@offset..].starts_with?({{pattern}})
        @offset += $0.size
        @column += $0.size
      end
    end

    # Returns the current word and consumes the next one.
    #
    # If in *verbal* lexical analysis mode (see `initialize(source, verbal)`),
    #
    # - Issues `INVALID_PSEUDOWORD`-typed `Word` instead of
    #   dying of "malformed input";
    #
    # - Makes words for characters matching `RX_IGNORE`, as
    #   opposed to ignoring them;
    #
    # - Does not omit the quotes of regexes and strings, the
    #   dollar in readtime symbols, etc.
    #
    # - Assigns type `KEYWORD` to keyword words
    def word!
      return @word if @word.type == "EOF"

      fresh =
        loop do
          break case
          when match(RX_IGNORE)
            @lineno += newlines = $0.count('\n')

            if newlines.zero?
              # There were no newlines. Just append the amount
              # of ignored characters.
              @column += $0.size - 1
            else
              # There were newlines. No matter how many of them,
              # since all characters in-between are ignored?
              @column = 1
            end

            @verbal ? word("IGNORE", $0) : next
          when pair = @context.triggers.find { |_, lead| match(lead) }
            word(pair[0], $0, $~.named_captures)
          when match(RX_SYMBOL)
            if keyword?($0)
              word(@verbal ? "KEYWORD" : $0.upcase, $0)
            elsif $0.size > 1 && $0.starts_with?("$")
              word("$SYMBOL", @verbal ? $0 : $0[1..])
            else
              word("SYMBOL", $0)
            end
          when match(RX_NUMBER)
            word("NUMBER", $0)
          when match(RX_STRING)
            # In $0, the quotes are present.
            word("STRING", @verbal ? $0 : $1)
          when match(RX_REGEX)
            # In $0, the quotes are present.
            word("REGEX", @verbal ? $0 : $1)
          when match(RX_SPECIAL)
            word($0.upcase, $0)
          when @offset == @source.size
            word("EOF", "")
          else
            if @verbal
              @offset += 1
              # An INVALID_PSEUDOWORD is issued when an invalid
              # character is met.
              word(INVALID_PSEUDOWORD, @source[@offset - 1].to_s)
            else
              raise ReadError.new(@source[@offset].to_s, @lineno, @file, "malformed input")
            end
          end
        end

      @word, _ = fresh, @word
    end

    # Returns the current word and consumes the next one, but
    # only if the current word is one of the given *types*.
    # Returns nil otherwise.
    def word!(*types : String)
      word! if @word.type.in?(types)
    end

    # Returns whether the current word's type is any of the
    # given *types*.
    def word?(*types : String)
      @word.type.in?(types)
    end

    # Returns the current word and consumes the next one,
    # but only if the current word is of one of the given
    # *types*. Dies of `ReadError` otherwise.
    def expect(*types : String)
      return word! if @word.type.in?(types)

      die("expected #{types.map(&.dump).join(", ")}")
    end

    # Same as `expect(types) && <...block...>`, but ensures
    # the result of the expression is a Quote.
    def after(*types : String, & : -> R) forall R
      (expect(*types) && yield).as(R)
    end

    # Same as `expect(types) && led`, but ensures the result
    # of the expression is a `Quote`.
    def after(*types : String)
      after(*types) { led }
    end

    # Yields and expects *type* to follow. If expectation
    # fulfilled, returns whatever the block returned.
    def before(type : String)
      value = yield; expect(type); value
    end

    # Reads a led, and expects *type* to folow it.
    def before(type : String)
      before(type) { led }
    end

    # Yields, then calls *succ*. If *succ* returned false,
    # dies of `ReadError`.
    #
    # Returns whatever the block returned.
    def before(succ : -> Bool)
      value = yield; succ.call || die("unexpected term"); value
    end

    # Yields repeatedly, expecting *sep* to follow each and
    # every time; stores the results of the yields in an Array,
    # and returns that array on termination. Termination happens
    # upon consuming *stop*.
    def repeat(stop : String? = nil, sep : String? = nil, & : -> T) forall T
      raise "repeat(): expected either stop or sep" unless stop || sep

      result = [] of T

      until stop && word!(stop)
        result << yield

        if stop && sep
          word!(sep) ? next : break expect(stop, sep)
        elsif sep && !word!(sep)
          break
        end
      end

      result
    end

    # Same as `repeat`, but with no block; defaults to
    # reading led.
    def repeat(stop : String? = nil, sep : String? = nil)
      repeat(stop, sep) { led }
    end

    # Reads a led expression with precedence *level* (see `Precedence`).
    def led(level = Precedence::ZERO) : Quote
      die("expected an expression") unless is_nud?

      left = nud_for(@word.type).parse!(self, tag, word!)

      # 'x' is special. If met in nud position, it's a symbol;
      # if met in operator position, it's a keyword operator.
      if @word.lexeme == "x"
        @word = word("X", "x")
      end

      while level.value < precedence.value
        left = led_for(@word.type).parse!(self, tag, left, word!)
      end

      left
    end

    # Returns whether the current word is one of the end-of-input
    # words (currently EOF, '}', ';').
    def eoi? : Bool
      word.type.in?("EOF", "}", ";")
    end

    # Reads a statement followed by a semicolon (if requested).
    #
    # Semicolons are always optional before `eoi?` words.
    def statement : Quote
      if stmt = @stmt[@word.type]?
        this = stmt.parse!(self, tag, word!)
        semi = stmt.semicolon
      else
        nud = nud_for?(@word.type)
        this = led
        # XXX: the decision made by *nud* remains with it
        # even after it finished reading. Doing a bit hairy
        # here; this may cause some problems.
        semi = nud.try(&.semicolon)
      end

      if !word!(";") && semi && !eoi?
        die("neither ';' nor end-of-input were found to end the statement")
      end

      this
    end

    # Reads multiple dot-separated symbols.
    #
    # SYMBOL {"." SYMBOL}
    private macro path
      repeat sep: "." { expect("SYMBOL").lexeme }
    end

    # Tries to read a 'distinct' statement.
    #
    # Returns the path of the distinct if found one, or nil
    # if did not.
    #
    # "distinct" PATH (';'? EOF | ';')
    def distinct? : Distinct?
      return unless word!("DISTINCT")

      before ->{ !!word!(";") || eoi? } { path }
    end

    # Tries to read a group of 'expose' statements separated
    # by semicolons.
    #
    # Returns an array of those exposes (may be empty if read
    # no exposes).
    #
    # {"expose" PATH (";" | EOI)}
    def exposes : Array(Distinct)
      exposes = [] of Distinct

      while word!("EXPOSE")
        exposes << path
        unless word!(";") || eoi?
          die("'expose': expected semicolon or end-of-input")
        end
      end

      exposes
    end

    # Yields top-level quotes to the block. Returns nothing.
    # Raises if this reader is dirty.
    #
    # To read `expose`s and `distinct`, call the appropriate
    # methods (`exposes`, `distinct?`) in the correct order
    # **before** attempting to `read`.
    def read
      raise "read(): dirty" if @dirty

      @dirty = true

      until word!("EOF")
        yield statement
      end
    end

    # Returns an array of top-level quotes. Raises if this
    # reader is dirty.
    #
    # To read `expose`s and `distinct`, call the appropriate
    # methods (`exposes`, `distinct?`) in the correct order
    # **before** attempting to `read`.
    def read
      quotes = Quotes.new

      read do |quote|
        quotes << quote
      end

      quotes
    end

    # Yields the words in the source string. Raises if this
    # reader is dirty.
    def words
      raise "words(): dirty" if @dirty

      @dirty = true

      until @word.type == "EOF"
        yield word!
      end
    end

    # Returns an array of words in the source string. Raises
    # if this reader is dirty.
    def words
      ary = [] of Word
      words { |it| ary << it }
      ary
    end

    # Returns whether the current word is a nud parselet of
    # type *pick*.
    def is_nud?(only pick : Parselet::Nud.class) : Bool
      !!nud_for?(@word.type).try(&.class.== pick)
    end

    # Returns whether the current word is a nud parselet of
    # any type except *pick*.
    def is_nud?(but pick : Parselet::Nud.class) : Bool
      !!nud_for?(@word.type).try(&.class.!= pick)
    end

    # Returns whether the current word is a nud parselet.
    def is_nud?
      !!nud_for?(@word.type)
    end

    # Returns whether the current word is a led parselet of
    # type *pick*.
    def is_led?(only pick : Parselet::Led.class) : Bool
      !!led_for?(@word.type).try(&.class.== pick)
    end

    # Returns whether the current word is a led parselet.
    def is_led?
      !!led_for?(@word.type)
    end

    # Returns whether the current word is a statement parselet.
    def is_stmt?
      @stmt.has_key?(@word.type)
    end

    # Declares a nud parselet.
    #
    # *trigger* is the type of a word that will invoke this
    # parselet.
    #
    # If the first item in *args* is
    #
    #   - a String, *args* (plus *trigger*) is interpreted as
    #   a list of unary operators (`PUnary`); *precedence*
    #   applies to each one of these operators;
    #
    #   - something other than a String, then that first item
    #   is interpreted as a nud parselet (subclass of `Nud`);
    #   *precedence* does not apply to it; the rest of *args*
    #   is thrown away.
    private macro defnud(trigger, *args, storage = @nud, precedence = PREFIX)
      {% unless args.first.is_a?(StringLiteral) %}
        {{storage}}[{{trigger}}] = {{args.first}}.new
      {% else %}
        {% for prefix in [trigger] + args %}
          {{storage}}[{{prefix}}] = Parselet::PUnary.new(Precedence::{{precedence}})
        {% end %}
      {% end %}
    end

    # Declares a led parselet.
    #
    # *trigger* is the type of a word that will invoke this
    # parselet.
    #
    # If the first item of *args* is
    #
    #   - a String, *args* (plus *trigger*) are interpreted
    #   as a list of binary operators (or, if got *common*,
    #   of triggers for *common*); *precedence* applies to
    #   each one of these operators;
    #
    #   - something other than a String, then that first item
    #   is interpreted as a led parselet (subclass of `Led`);
    #   *precedence* is applied to it; the rest of *args* is
    #   thrown away.
    private macro defled(trigger, *args, common = Parselet::PBinary, precedence = ZERO)
      {% if args.first && !args.first.is_a?(StringLiteral) %}
        @led[{{trigger}}] = {{args.first}}.new(Precedence::{{precedence}})
      {% else %}
        {% for binary in [trigger] + args %}
          @led[{{binary}}] = {{common}}.new(Precedence::{{precedence}})
        {% end %}
      {% end %}
    end

    # Declares a statement parselet.
    #
    # *trigger* is the type of a word that will invoke this
    # parselet.
    #
    # To see how *args* are interpreted, look at `defnud`.
    private macro defstmt(trigger, *args)
      defnud({{trigger}}, {{*args}}, storage: @stmt)
    end

    # Declares all parselets.
    def prepare
      # Prefixes (NUDs):

      defnud("+", "-", "~", "&", "#", "%", "NOT", "TO", "FROM")

      defnud("TRUE", Parselet::PTrue)
      defnud("FALSE", Parselet::PFalse)
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
      defnud("_", Parselet::PSuperlocalTake)
      defnud("&_", Parselet::PSuperlocalTap)
      defnud("'", Parselet::PPattern)
      defnud("<", Parselet::PReadtimeEnvelope)
      defnud("%{", Parselet::PMap)

      # Infixes (LEDs):

      defled("=", ":=",
        common: Parselet::PAssign,
        precedence: ASSIGNMENT)

      defled("+=", "-=", "*=", "/=", "~=", "&=",
        common: Parselet::PBinaryAssign,
        precedence: ASSIGNMENT)

      defled("DIES", Parselet::PDies, precedence: CONVERT)
      defled("AND", "OR", precedence: JUNCTION)
      defled("IS", "IN", ">", "<", ">=", "<=", precedence: IDENTITY)
      defled("TO", precedence: RANGE)
      defled("+", "-", "~", "&", "%", precedence: ADDITION)
      defled("*", "/", "X", precedence: PRODUCT)
      defled("++", Parselet::PReturnIncrement, precedence: POSTFIX)
      defled("--", Parselet::PReturnDecrement, precedence: POSTFIX)
      defled("?", Parselet::PIntoBool, precedence: CALL)
      defled("(", Parselet::PCall, precedence: CALL)
      defled("[", Parselet::PAccess, precedence: FIELD)
      defled(".", Parselet::PAccessField, precedence: FIELD)

      # Statements:

      # Always dies (see `exposes?`):
      defstmt("EXPOSE", Parselet::PExpose)
      # Always dies (see `distinct?`):
      defstmt("DISTINCT", Parselet::PDistinct)

      defstmt("NUD", Parselet::PDefineNud)
      defstmt("FUN", Parselet::PFun)
      defstmt("BOX", Parselet::PBox)
      defstmt("IMMEDIATE", Parselet::PImmediateBox)
      defstmt("LOOP", Parselet::PLoop)
      defstmt("RETURN", Parselet::PReturnStatement)

      self
    end

    def to_s(io)
      io << "<reader for '#{@file}'>"
    end

    # A shorthand for `Reader#read`. **Ignores `expose` and
    # `distinct` statements.**
    def self.read(source : String, file = "untitled", context = CxReader.new, enquiry = Enquiry.new)
      reader = new(source, file, context, enquiry)
      reader.distinct?
      reader.exposes
      reader.read
    end

    # :ditto:
    def self.read(source : String, file = "untitled", context = CxReader.new, enquiry = Enquiry.new)
      reader = new(source, file, context, enquiry)
      reader.distinct?
      reader.exposes?
      reader.read do |quote|
        yield quote
      end
    end

    # A shorthand for `Reader#words`. Initializes the reader in
    # verbal mode (see `Reader#word!`).
    def self.words(source : String, context = CxReader.new)
      new(source, verbal: true, context: context).words do |word|
        yield word
      end
    end

    # :ditto:
    def self.words(source : String, context = CxReader.new)
      new(source, verbal: true, context: context).words
    end
  end
end
