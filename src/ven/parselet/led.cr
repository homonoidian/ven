require "./nud"

module Ven::Parselet
  include Suite

  # A parser that is invoked by a left-denotated word.
  #
  # Left denotation is when something to the left of the
  # current word assigns meaning to the current word itself.
  abstract class Led
    # The reader that asked for this led to be parsed.
    @parser = uninitialized Reader

    # Whether a semicolon must follow this led.
    getter semicolon = true
    # The precedence of this led.
    getter precedence : Precedence = Precedence::ZERO

    # Makes a led with precedence *precedence*.
    def initialize(@precedence = Precedence::ZERO)
    end

    # Dies of `ReadError` given *message*, which should explain
    # why the error happened.
    def die(message : String)
      @parser.die(message)
    end

    # Returns the type of *token*.
    #
    # *token* defaults to `token`, which is the standard name
    # of the lead token in `parse`.
    macro type(token = token)
      {{token}}[:type]
    end

    # Returns the lexeme of *token*.
    #
    # *token* defaults to `token`, which is the standard name
    # of the lead token in `parse`.
    macro lexeme(token = token)
      {{token}}[:lexeme]
    end

    # Reads a symbol if *token* is nil (orelse uses the value
    # of *token*) and creates the corresponding symbol quote.
    def symbol(tag, token = nil) : QSymbol
      token ||= @parser.expect("$SYMBOL", "SYMBOL", "*")

      case type
      when "$SYMBOL"
        QReadtimeSymbol.new(tag, lexeme)
      when "SYMBOL", "*"
        QRuntimeSymbol.new(tag, lexeme)
      else
        raise "unknown symbol type"
      end
    end

    # Reads a block under the jurisdiction of this led. Returns
    # the statements of the block. If *opening* is false, the
    # opening paren won't be read.
    def block(opening = true, @semicolon = false)
      @parser.expect("{") if opening
      @parser.repeat("}", unit: -> @parser.statement)
    end

    # Reads a led under the jurisdiction of this led and with
    # the precedence of this led.
    def led(precedence = @precedence)
      @parser.led(precedence)
    end

    # Evaluates *consequtive* if read *word*; otherwise,
    # evaluates *alternative*.
    macro if?(word, then consequtive, else alternative = nil)
      @parser.word!({{word}}) ? {{consequtive}} : {{alternative}}
    end

    # Performs the parsing.
    #
    # Subclasses of `Led` should not override this method. Instead,
    # they should override `parse`.
    def parse!(@parser : Ven::Reader, tag : QTag, left : Quote, token : Ven::Word)
      parse(tag, left, token)
    end

    # Performs the parsing.
    abstract def parse(tag : QTag, left : Quote, token : Word)
  end

  # Reads a binary operation into QBinary.
  class PBinary < Led
    # A list of binary operator word types that can be followed
    # by `not`.
    NOTTABLE = %(IS)

    def parse(tag, left, token)
      notted = type(token).in?(NOTTABLE) && !!@parser.word!("NOT")

      quote = QBinary.new(tag, lexeme(token), left, led)
      quote = QUnary.new(tag, "not", quote) if notted

      quote
    end
  end

  # Reads a call into QCall.
  class PCall < Led
    def parse(tag, left, token)
      QCall.new(tag, left, @parser.repeat(")", ","))
    end
  end

  # Reads an assignment expression into QAssign.
  class PAssign < Led
    def parse(tag, left, token)
      QAssign.new(tag, validate(left), led, type(token) == ":=")
    end

    # Returns whether *left* is a valid assignment target.
    def validate?(left : Quote) : Bool
      left.is_a?(QSymbol) && left.value != "*"
    end

    # Returns *left* if it is a valid assignment target, or
    # dies of `ReadError`.
    def validate(left : Quote)
      die("illegal assignment target") unless validate?(left)

      left.as(QSymbol)
    end
  end

  # Reads a binary operator assignment expression into QBinaryAssign.
  class PBinaryAssign < PAssign
    def parse(tag, left, token)
      QBinaryAssign.new(tag, type(token)[0].to_s, validate(left), led)
    end
  end

  # Reads an into-bool expression into QIntoBool.
  class PIntoBool < Led
    def parse(tag, left, token)
      QIntoBool.new(tag, left)
    end
  end

  # Reads a return-increment expression into QReturnIncrement.
  class PReturnIncrement < Led
    def parse(tag, left, token)
      die("postfix '++' expects a symbol") unless left.is_a?(QSymbol)

      QReturnIncrement.new(tag, left)
    end
  end

  # Reads a return-decrement expression into QReturnDecrement.
  class PReturnDecrement < Led
    def parse(tag, left, token)
      die("postfix '--' expects a symbol") unless left.is_a?(QSymbol)

      QReturnDecrement.new(tag, left)
    end
  end

  # Reads a field access expression into QAccessField.
  #
  # Also reads dynamic field access (`a.(b)`) and branches
  # field access (`a.[b.c, d]`).
  class PAccessField < Led
    def parse(tag, left, token)
      QAccessField.new(tag, left, accesses)
    end

    # Reads the accesses (things that are are separated by dots).
    private def accesses
      @parser.repeat(sep: ".", unit: -> access)
    end

    # Reads an individual field access.
    #
    # Branches access, dynamic field access and immediate field
    # access are supported.
    private def access
      lead = @parser.expect("[", "(", "SYMBOL")

      case type lead
      when "["
        FABranches.new(branches)
      when "("
        FADynamic.new(dynamic)
      when "SYMBOL"
        FAImmediate.new(lexeme lead)
      else
        raise "PAccessField#access(): unknown lead type"
      end
    end

    # Reads a branches field access, which is basically a
    # vector (`PVector`).
    private def branches
      PVector.new.parse!(@parser, QTag.void, word?)
    end

    # Reads a dynamic field access, which is basically a
    # grouping (`PGroup`).
    private def dynamic
      PGroup.new.parse!(@parser, QTag.void, word?)
    end

    # Makes up a word.
    private macro word?
      { type: ".", lexeme: ".", line: 1 }
    end
  end

  # Reads postfix 'dies' into a QDies: `1 dies`,
  # `die("hi") dies`, etc.
  class PDies < Led
    def parse(tag, left, token)
      QDies.new(tag, left)
    end
  end
end
