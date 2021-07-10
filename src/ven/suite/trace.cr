module Ven::Suite
  # Represents an individual trace entry in an error's
  # traceback.
  struct Trace
    include JSON::Serializable

    getter file : String
    getter line : Int32
    getter desc : String

    def initialize(tag : QTag, @desc)
      @line = tag.line
      @file = tag.file
    end

    def initialize(@file, @line, @desc)
    end

    def ==(tag : QTag)
      @file == tag.file && @line == tag.line
    end

    def ==(trace : Trace)
      @file == trace.file && @line == trace.line && @desc == trace.desc
    end

    # Stringifies this trace.
    #
    # Reads the file to provide the excerpt, unless the file
    # does not exist.
    #
    # Colorizes the output.
    def to_s(io)
      io << "  in #{@desc.colorize.bold} (#{@file}:#{@line})"
      if File.exists?(@file)
        excerpt = File.read_lines(@file)[@line - 1]
        io << "\n    #{@line}| #{excerpt.lstrip}"
      end
    end

    def_clone
  end

  alias Traces = Array(Trace)
end
