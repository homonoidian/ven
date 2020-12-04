module Ven
  class ParseError < Exception
    getter char, line, file, message

    def initialize(token : Token, @file : String, @message : String)
      @char = token[:raw]
      @line = token[:line]
    end

    def initialize(
      @char : String,
      @line : Int32,
      @file : String,
      @message : String)
    end
  end

  class RuntimeError < Exception
    getter file, line, message

    @file : String
    @line : Int32

    def initialize(tag : QTag, @message : String)
      @file = tag.file
      @line = tag.line
    end
  end

  class InternalError < Exception
    getter message

    def initialize(
      @message : String)
    end
  end
end
