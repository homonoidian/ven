require "./parselet"

module Ven::Parselet
  include Suite

  # A kind of parselet that is invoked by a left-denotated
  # word (a word that follows a full nud).
  abstract class Led < Parselet
    @left = uninitialized Quote

    # Invokes this parselet.
    #
    # *parser* is the parser that invoked this parselet; *tag*
    # is the location of the invokation; *left* is the nud
    # that preceded the led word; *token* is the left-denotated
    # word that invoked this parselet.
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

  # Reads a binary operation into QBinary.
  class PBinary < Led
    # A list of binary operator word types that can be
    # followed by `not`.
    NOTTABLE = %(IS)

    def parse
      notted = type.in?(NOTTABLE) && !!@parser.word!("NOT")
      quote  = QBinary.new(@tag, lexeme, @left, led)
      quote  = QUnary.new(@tag, "not", quote) if notted
      quote
    end
  end

  # Reads a call into QCall.
  class PCall < Led
    def parse
      QCall.new(@tag, @left, @parser.repeat(")", ","))
    end
  end

  # Reads an assignment expression into QAssign.
  class PAssign < Led
    def parse
      QAssign.new(@tag, validate, led, type == ":=")
    end

    # Returns whether this assignment is valid.
    #
    # '$' and '*' are currently considered invalid assignment
    # targets, for expressions like `* = 3`, `$ = 5` may produce
    # unwanted behavior (especially the latter).
    def validate? : Bool
      !@left.as?(QSymbol).try &.value.in?('$', '*') || !@left.is_a?(QCall)
    end

    # Returns *@left* if it is a valid assignment target, orelse
    # dies of `ReadError`.
    def validate
      validate? ? @left : die("illegal assignment target")
    end
  end

  # Reads a binary operator assignment expression into QBinaryAssign.
  class PBinaryAssign < PAssign
    def parse
      # type = '+=' ==> ['+', '=']; type = '++=' ==> ['++', '='].
      QBinaryAssign.new(@tag, type.split('=', 2)[0], validate, led)
    end
  end

  # Reads an into-bool expression into QIntoBool.
  class PIntoBool < Led
    def parse
      QIntoBool.new(@tag, @left)
    end
  end

  # Reads a return-increment expression into QReturnIncrement.
  class PReturnIncrement < Led
    def parse
      QReturnIncrement.new(@tag, @left.as?(QSymbol) || die "'++' expects a symbol")
    end
  end

  # Reads a return-decrement expression into QReturnDecrement.
  class PReturnDecrement < Led
    def parse
      QReturnDecrement.new(@tag, @left.as?(QSymbol) || die "'--' expects a symbol")
    end
  end

  # Reads a field access expression into QAccessField.
  class PAccessField < Led
    def parse
      QAccessField.new(@tag, @left, accesses)
    end

    # Reads multiple accesses (`access` units separated by dots).
    private def accesses
      @parser.repeat(sep: ".") { access }
    end

    # Reads an individual field access. This includes branches
    # access, dynamic field access, or immediate field access.
    private def access
      lead = @parser.expect("[", "(", "SYMBOL")

      case lead[:type]
      when "["
        FABranches.new(branches)
      when "("
        FADynamic.new(dynamic)
      when "SYMBOL"
        FAImmediate.new(lead[:lexeme])
      else
        raise "PAccessField#access(): unknown lead type"
      end
    end

    # Reads a branches field access, which is basically a
    # vector (`PVector`).
    private def branches
      PVector.new.parse!(@parser, @tag, @token)
    end

    # Reads a dynamic field access, which is basically a
    # grouping (`PGroup`).
    private def dynamic
      PGroup.new.parse!(@parser, @tag, @token)
    end
  end

  # Reads postfix 'dies' into a QDies: `1 dies`,
  # `die("hi") dies`, etc.
  class PDies < Led
    def parse
      QDies.new(@tag, @left)
    end
  end
end
