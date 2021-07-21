module Ven::Suite
  # Represents an individual trace entry in an error's
  # traceback.
  struct Trace
    # The amount of whitespace characters before a trace.
    TRACE_PADDING = 2

    # Returns the line that this trace points to.
    getter line : Int32
    # Returns the file that this trace points to.
    getter file : String
    # Returns the description of this trace.
    getter desc : String

    # Initializes from `QTag`.
    def initialize(tag : QTag, @desc)
      @line = tag.line
      @file = tag.file
    end

    # Initializes from *file*, *line*.
    def initialize(@file, @line, @desc)
    end

    # Returns whether this trace points to the same location
    # as `QTag` *tag*.
    def ==(tag : QTag)
      @file == tag.file && @line == tag.line
    end

    # Returns whether this trace points to the same location
    # as the *other* trace.
    def ==(other : Trace)
      @file == other.file && @line == other.line && @desc == other.desc
    end

    # Returns the string representation of this trace.
    #
    # Reads `file` for an excerpt, unless it isn't a file or
    # doesn't exist. **Colorizes.**
    def to_s(io)
      io << " " * TRACE_PADDING << @desc.colorize.bold
      io << " (" << @file << ":" << @line << ")"

      # If *file* exists, is a file, and is able to provide
      # *line*, append the line preview.
      if File.file?(@file) && (excerpt = File.read_lines(@file)[@line - 1]?)
        io << "\n" << " " * (TRACE_PADDING + 2)
        io << @line << "| " << excerpt.lstrip
      end
    end

    def_clone
  end

  alias Traces = Array(Trace)
end
