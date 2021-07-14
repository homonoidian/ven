module Ven::Suite
  # The base class of all Ven exceptions.
  class VenError < Exception
  end

  # Raised when the reader is given malformed or illegal input,
  # or when the lexical analyzer receives invalid input.
  class ReadError < VenError
    # Returns the line where this error happened.
    getter line : Int32
    # Returns the file where this error happened.
    getter file : String
    # Returns the lexeme nearest to the place-of-interest.
    getter lexeme : String?

    # Initializes from a lexical error.
    def initialize(@lexeme, @line, @file, @message)
    end

    # Initializes from a reader error.
    def initialize(word : Word, @file, @message)
      @line = word[:line]
      @lexeme = word[:lexeme]
    end

    # Initializes from a readtime error.
    def initialize(tag : QTag, @message)
      @line = tag.line
      @file = tag.file
    end

    # Returns a JSON object that represents this error.
    #
    # Note that it is purely representative. There is no way
    # to restore the original error from it.
    def to_json(json : JSON::Builder)
      json.object do
        json.field("Type", "ReadError")
        json.field("Payload", {
          "Line"   => @line,
          "File"   => @file,
          "Lexeme" => @lexeme,
        })
      end
    end
  end

  # Raised when the compiler encounters a semantic error.
  class CompileError < VenError
    # Returns the traceback.
    getter traces : Traces

    def initialize(@traces, @message)
    end

    # Returns a JSON object that represents this error.
    #
    # Note that it is purely representative. There is no way
    # to restore the original error from it.
    def to_json(json : JSON::Builder)
      json.object do
        json.field("Type", "CompileError")
        json.field("Payload", {
          "Traces"  => @traces,
          "Message" => @message,
        })
      end
    end
  end

  # Raised when the interpreter encounters a semantic error.
  class RuntimeError < VenError
    # Returns the line where this error happened.
    getter line : Int32
    # Returns the file where this error happened.
    getter file : String
    # Returns the traceback.
    getter traces : Traces

    def initialize(@traces, @file, @line, @message)
    end

    # Returns a JSON object that represents this error.
    #
    # Note that it is purely representative. There is no way
    # to restore the original error from it.
    def to_json(json : JSON::Builder)
      json.object do
        json.field("Type", "RuntimeError")
        json.field("Payload", {
          "File"    => @file,
          "Line"    => @line,
          "Traces"  => @traces,
          "Message" => @message,
        })
      end
    end
  end

  # Raised when there is an error in the interpreter implementation
  # itself. InternalErrors are not as bad (nor as dangerous) as
  # standard Crystal errors: if a standard Crystal error is raised,
  # something is **very** wrong (for the user, at least).
  #
  # Note that internal errors have no traceback/line number
  # associated with them, so make sure to raise with unique/
  # searchable error messages.
  class InternalError < VenError
    # Returns a JSON object that represents this error.
    #
    # Note that it is purely representative. There is no way
    # to restore the original error from it.
    def to_json(json : JSON::Builder)
      json.object do
        json.field("Type", "InternalError")
        json.field("Payload", {
          "Message" => @message,
        })
      end
    end
  end

  # Raised when there is an error in the process of exposing
  # a distinct.
  class ExposeError < VenError
    # Returns a JSON object that represents this error.
    #
    # Note that it is purely representative. There is no way
    # to restore the original error from it.
    def to_json(json : JSON::Builder)
      json.object do
        json.field("Type", "ExposeError")
        json.field("Payload", {
          "Message" => @message,
        })
      end
    end
  end
end
