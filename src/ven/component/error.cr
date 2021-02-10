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

  # An exception that is raised when there is an error in the
  # interpreter implementation itself. InternalErrors are not
  # as bad (or as dangerous) as standard Crystal errors: if
  # a standard Crystal error is raised, something is **very**
  # wrong.
  class InternalError < VenError
    getter message

    def initialize(
      @message : String)
    end
  end

  # An exception that is raised when there is a problem in the
  # relationship between different files and modules, or in the
  # relationship between the reader and the interpreter.
  class WorldError < VenError
    getter file, line, message

    @file : String
    @line : UInt32

    def initialize(tag : QTag, @message : String)
      @file = tag.file
      @line = tag.line
    end

    def initialize(@message : String)
      @file = "<unknown (probably origin)>"
      @line = 1
    end
  end
end
