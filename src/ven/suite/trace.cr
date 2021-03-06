module Ven::Suite
  # Some evaluations leave a trace to lead the user to the
  # actual source of an error, if one occurs.
  class Trace
    getter tag : QTag
    getter name : String

    def initialize(@tag, @name)
    end

    # Returns the string representation of this Trace. Can
    # highlight (brighten) the `name` of this trace if
    # *highlight* is true.
    def to_s(io : IO, highlight = true)
      hi_name = @name
        .colorize
        .bright
        .toggle(highlight)

      io << hi_name << " (" << @tag.file << ":" << @tag.line << ")"
    end
  end

  alias Traces = Array(Trace)
end
