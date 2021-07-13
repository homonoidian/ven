module Ven::Parselet
  # If the value is > 0, then we're reading in a readtime
  # context (nud, led, etc.) If it's 0, we're reading outside
  # of a readtime context.
  class_property in_readtime_context = 0

  abstract class Parselet
    # The current location (see `QTag`)
    @tag = uninitialized QTag

    # The word that invoked this parselet.
    @token = uninitialized Word

    # A reference to the `Reader` that invoked this parselet
    @parser = uninitialized Reader

    # Returns whether a semicolon must follow this parselet.
    getter semicolon = true

    # Returns the precedence of this parselet.
    getter precedence = Precedence::ZERO

    # Makes a parselet with the given *precedence*.
    def initialize(@precedence = Precedence::ZERO)
    end

    # Invokes this parselet.
    #
    # Although it's not abstract, all subclasses must implement
    # this method.
    def parse!(*args)
      raise "not implemented"
    end

    # Dies of `ReadError` with the given *message*.
    macro die(message)
      @parser.die({{message}})
    end

    # A shorthand for `@token[:type]`.
    macro type
      @token[:type]
    end

    # A shorthand for `@token[:lexeme]`
    macro lexeme
      @token[:lexeme]
    end

    # Enables readtime context in the block. Returns the
    # block's value.
    macro in_readtime_context
      Ven::Parselet.in_readtime_context += 1
      begin
        %result = {{yield}}
      ensure
        Ven::Parselet.in_readtime_context -= 1
      end
      %result
    end

    # Returns whether the reading happens in a readtime
    # context. Please use this macro instead of working
    # with `Parselet.in_readtime_context` yourself.
    macro in_readtime_context?
      Ven::Parselet.in_readtime_context > 0
    end

    # Returns the proper symbol quote for *token* if it's nil.
    # Alternatively, reads a symbol and makes the appropriate
    # symbol quote.
    def symbol(token = nil) : QSymbol
      token ||= @parser.expect("$SYMBOL", "SYMBOL", "*")

      case token[:type]
      when "$SYMBOL"
        unless in_readtime_context?
          die("readtime symbol (namely '#{token[:lexeme]}') used " \
              "outside of readtime evaluation context")
        end

        QReadtimeSymbol.new(@tag, token[:lexeme])
      when "SYMBOL", "*"
        QRuntimeSymbol.new(@tag, token[:lexeme])
      else
        raise "unknown symbol type"
      end
    end

    # Reads a Ven block (`{ ... }`).
    #
    # Returns the quotes in the block.
    #
    # If *opening* is false, it does not expect the opening
    # paren. Expects semicolon depending on *semicolon*.
    def block(opening = true, @semicolon = false) : Quotes
      @parser.expect("{") if opening
      @parser.repeat("}") { @parser.statement }
    end

    # Reads a led of the given *precedence*.
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
