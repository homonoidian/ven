module Ven::Suite
  # Some evaluations leave a trace to lead the user to the
  # actual source of an error, if one occurs.
  class Trace
    getter tag : QTag
    getter name : String
    getter file : String
    getter line : UInt32

    def initialize(@tag, @name)
      @file = tag.file
      @line = tag.line
    end

    # Returns the string representation of this Trace. Can
    # highlight (brighten) the `name` of this trace if
    # *highlight* is true.
    def to_s(io : IO, highlight = true)
      hi_name = @name
        .colorize
        .bright
        .toggle(highlight)

      io << hi_name << " (" << @file << ":" << @line << ")"
    end
  end

  alias Traces = Array(Trace)
end
