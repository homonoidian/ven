module Ven::Component
  # Some evaluations leave a trace to lead the user to the
  # actual source of an error, if one occurs.
  class Trace
    getter tag : QTag
    getter name : String

    def initialize(@tag, @name)
    end

    def to_s(io)
      io << "'" << @name << "' " << "(" << @tag.file << ":" << @tag.line << ")"
    end
  end

  alias Traces = Array(Trace)
end
