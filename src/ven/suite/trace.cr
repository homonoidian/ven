module Ven::Suite
  # Represents an individual trace entry in an error's
  # traceback.
  struct Trace
    getter file : String
    getter line : UInt32
    getter name : String

    def initialize(tag : QTag, @name)
      @line = tag.line
      @file = tag.file
    end

    def initialize(@file, @line, @name)
    end

    # NOTE: reads the file to provide the excerpt, unless
    # the file does not exist.
    def to_s(io)
      io << "  in #{@name} (#{@file}:#{@line})"

      if File.exists?(@file)
        excerpt = File.read_lines(@file)[@line - 1]

        io << "\n    #{@line}| #{excerpt}"
      end
    end
  end

  alias Traces = Array(Trace)
end
