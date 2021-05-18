require "./share"

module Ven::Parselet
  include Suite

  # A parser that is invoked by a left-denotated word.
  #
  # Left denotation is when something to the left of the
  # current word assigns meaning to the current word itself.
  abstract class Led < Parselet::Share
    # Performs the parsing.
    #
    # Subclasses of `Led` should not override this method.
    # They should (actually, must) implement `parse` instead.
    def parse!(@parser : Ven::Reader, tag : QTag, left : Quote, token : Ven::Word)
      # Reset the semicolon want each pass.
      @semicolon = true

      parse(tag, left, token)
    end

    # Performs the parsing.
    #
    # All subclasses of `Led` should implement this method.
    abstract def parse(tag : QTag, left : Quote, token : Word)
  end

  # Reads a binary operation into QBinary.
  class PBinary < Led
    # A list of binary operator word types that can be followed
    # by `not`.
    NOTTABLE = %(IS)

    def parse(tag, left, token)
      notted = type.in?(NOTTABLE) && !!@parser.word!("NOT")

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
      QAssign.new(tag, validate(left), led, type == ":=")
    end

    # Returns whether *left* is a valid assignment target.
    def validate?(left : QSymbol) : Bool
      !left.value.in?("$", "*")
    end

    # :ditto:
    def validate?(left : QCall)
      true
    end

    # :ditto:
    def validate?(left)
      false
    end

    # Returns *left* if it is a valid assignment target, or
    # dies of `ReadError`.
    def validate(left : Quote)
      die("illegal assignment target") unless validate?(left)

      left
    end
  end

  # Reads a binary operator assignment expression into QBinaryAssign.
  class PBinaryAssign < PAssign
    def parse(tag, left, token)
      QBinaryAssign.new(tag, type[0].to_s, validate(left), led)
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
