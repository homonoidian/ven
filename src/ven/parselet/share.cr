module Ven::Parselet
  # Various methods and properties shared by the two parselet
  # kinds, `Nud` and `Led`.
  abstract class Share
    # The reader that asked for this parselet to be parsed.
    @parser = uninitialized Reader

    # Whether a semicolon must follow this parselet.
    getter semicolon = true
    # The precedence of this parselet (experimental for nuds).
    getter precedence : Precedence = Precedence::ZERO

    # Makes a parselet with precedence *precedence*.
    #
    # NOTE: Having *precedence* is experimental for nuds.
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

    # Reads a block under the jurisdiction of this parselet.
    #
    # Returns the statements of the block.
    #
    # If *opening* is false, the opening paren won't be read.
    def block(opening = true, @semicolon = false)
      @parser.expect("{") if opening
      @parser.repeat("}", unit: -> @parser.statement)
    end

    # Reads a led under the jurisdiction of this parselet, with
    # the precedence of this parselet.
    def led(precedence = @precedence)
      @parser.led(precedence)
    end

    # Evaluates *consequtive* if read *word*; otherwise,
    # evaluates *alternative*.
    macro if?(word, then consequtive, else alternative = nil)
      @parser.word!({{word}}) ? {{consequtive}} : {{alternative}}
    end
  end
end
