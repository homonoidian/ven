module Ven::Suite
  # The base class of all Ven-related exceptions.
  class VenError < Exception
  end

  # The exception that is raised when the reader is given
  # malformed or illegal input, or when the lexical analyzer
  # receives invalid input.
  class ReadError < VenError
    getter line : UInt32
    getter file : String
    getter lexeme : String

    # Initializes a lexical error.
    def initialize(@lexeme, @line, @file, @message)
    end

    # Initializes a reader error.
    def initialize(word : Word, @file, @message)
      @line = word[:line]
      @lexeme = word[:lexeme]
    end
  end

  # The exception that is raised when the interpreter
  # encounters a traceable semantic error.
  class RuntimeError < VenError
    getter file : String
    getter line : UInt32

    def initialize(@file, @line, @message)
    end
  end

  # An exception that is raised when there is an error in the
  # interpreter implementation itself. InternalErrors are not
  # as bad (nor as dangerous) as standard Crystal errors: if
  # a standard Crystal error is raised, something is **very**
  # wrong.
  class InternalError < VenError
  end
end
