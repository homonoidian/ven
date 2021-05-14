module Ven::Suite
  # Represents an individual trace entry in an error's
  # traceback.
  struct Trace
    getter file : String
    getter line : Int32
    getter name : String

    def initialize(tag : QTag, @name)
      @line = tag.line
      @file = tag.file
    end

    def initialize(@file, @line, @name)
    end

    def ==(tag : QTag)
      @file == tag.file && @line == tag.line
    end

    # Stringifies this trace.
    #
    # Reads the file to provide the excerpt, unless the file
    # does not exist.
    #
    # Colorizes the output.
    def to_s(io)
      io << "  in #{@name.colorize.bold} (#{@file}:#{@line})"

      if File.exists?(@file)
        excerpt = File.read_lines(@file)[@line - 1]

        io << "\n    #{@line}| #{excerpt.lstrip}"
      end
    end
  end

  alias Traces = Array(Trace)
end
