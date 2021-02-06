module Ven::Component
  # The base class of all Ven-related exceptions.
  class VenError < Exception
  end

  # The exception that is raised when the reader is given
  # malformed or illegal input, and also when the lexical
  # analyzer receives invalid input.
  class ReadError < VenError
    getter lexeme, line, file, message

    # Initializes a parser error.
    def initialize(token : Token, @file : String, @message : String)
      @line = token[:line]
      @lexeme = token[:lexeme]
    end

    # Initializes a lexical error.
    def initialize(
      @lexeme : String,
      @line : UInt32,
      @file : String,
      @message : String)
    end
  end

  # The exception that is raised when the interpreter
  # encounters a traceable semantic error (error in the
  # meaning of a program), or a 'die' call.
  class RuntimeError < VenError
    getter file, line, message

    @file : String
    @line : UInt32

    def initialize(tag : QTag, @message : String)
      @file = tag.file
      @line = tag.line
    end
  end

  # An untraceable error that is raised when a semantic error
  # is caught in the interpreter implementation itself. Note
  # that not all errors are captured that way and boxed into
  # an InternalError. Many cause standard Crystal runtime errors;
  # these are more dangerous and uncomfortable than the former.
  class InternalError < VenError
    getter message

    def initialize(
      @message : String)
    end
  end
end
