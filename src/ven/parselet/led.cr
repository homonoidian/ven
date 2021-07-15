require "./parselet"

module Ven::Parselet
  include Suite

  # A kind of parselet that is invoked by a left-denotated
  # word (a word that follows a full nud).
  abstract class Led < Parselet
    @left = uninitialized Quote

    # Invokes this parselet.
    #
    # *parser* is a reference to the `Reader` that invoked this
    # parselet. *tag* is the current location (see `QTag`). *left*
    # is the full nud preceding the left-denotated word. *token* is
    # the left-denotated word.
    def parse!(@parser, @tag, @left : Quote, @token)
      # Reset the semicolon decision each parse!(), so as to
      # not get deceived by that made by a previous parse!().
      @semicolon = true

      parse
    end

    # Performs the parsing.
    #
    # All subclasses of `Led` should implement this method.
    abstract def parse
  end

  # Reads a binary operation into `QBinary`.
  class PBinary < Led
    # A list of binary operator word types that can be
    # followed by `not`.
    NOTTABLE = %(IS)

    def parse
      notted = type.in?(NOTTABLE) && !!@parser.word!("NOT")
      quote = QBinary.new(@tag, lexeme, @left, led)
      quote = QUnary.new(@tag, "not", quote) if notted
      quote
    end
  end

  # Reads a call into `QCall`.
  class PCall < Led
    def parse
      QCall.new(@tag, @left, @parser.repeat(")", ","))
    end
  end

  # Reads an assignment expression into `QAssign`.
  class PAssign < Led
    def parse
      QAssign.new(@tag, validate, led, type == ":=")
    end

    # Returns whether the left-hand side of this assignment
    # is valid.
    #
    # '$' and '*' are currently considered invalid left-hand
    # sides, as expressions like `* = 3`, `$ = 5` produce
    # unwanted behavior (especially the latter).
    def validate? : Bool
      @left.as?(QSymbol).try { |it| !it.value.in?("$", "*") } ||
        @left.is_a?(QAccess)
    end

    # Returns *@left* if it is a valid assignment target
    # (see `validate?`), otherwise dies of `ReadError`.
    def validate
      validate? ? @left : die("illegal assignment target")
    end
  end

  # Reads a binary operator assignment expression into `QBinaryAssign`.
  class PBinaryAssign < PAssign
    def parse
      # Say, if type = '+=':
      #   ['+', '=']
      # Or if type = '++=':
      #   ['++', '=']
      operator = type.split('=', 2)[0]

      QBinaryAssign.new(@tag, operator, validate, led)
    end
  end

  # Reads an into-bool expression into `QIntoBool`.
  class PIntoBool < Led
    def parse
      QIntoBool.new(@tag, @left)
    end
  end

  # Reads a return-increment (`foo++`) expression into
  # `QReturnIncrement`.
  class PReturnIncrement < Led
    def parse
      QReturnIncrement.new(@tag,
        @left.as?(QSymbol) || die("'++' expects a symbol"))
    end
  end

  # Reads a return-decrement (`foo--`) expression into
  # `QReturnDecrement`.
  class PReturnDecrement < Led
    def parse
      QReturnDecrement.new(@tag,
        @left.as?(QSymbol) || die("'--' expects a symbol"))
    end
  end

  # Reads access (aka subscript) expression into `QAccess`.
  class PAccess < PCall
    def parse
      QAccess.new(@tag, @left, @parser.repeat("]", ","))
    end
  end

  # Reads a field access expression into `QAccessField`.
  class PAccessField < Led
    def parse
      QAccessField.new(@tag, @left, members)
    end

    # Reads field access members (`access`es separated by dots).
    private def members
      @parser.repeat(sep: ".") { access }
    end

    # Reads an individual field access into the corresponding
    # `FieldAccess` struct. This includes branches access
    # (`FABranches`), dynamic field access (`FADynamic`), or
    # immediate field access (`FAImmediate`).
    private def access
      if @parser.word!("[")
        FABranches.new(branches_access)
      elsif @parser.word!("(")
        FADynamic.new(dynamic_access)
      else
        FAImmediate.new(symbol)
      end
    end

    # Reads a branches field access, which is essentially a
    # vector (`PVector`).
    private def branches_access
      PVector.new.parse!(@parser, @tag, @token)
    end

    # Reads a dynamic field access, which is essentially a
    # grouping (`PGroup`).
    private def dynamic_access
      PGroup.new.parse!(@parser, @tag, @token)
    end
  end

  # Reads postfix 'dies' into `QDies`.
  class PDies < Led
    def parse
      QDies.new(@tag, @left)
    end
  end
end
