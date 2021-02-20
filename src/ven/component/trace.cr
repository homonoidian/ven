module Ven::Component
  alias Traces = Array(Trace)

  # Some evaluations leave a trace to lead the user to the
  # actual source of an error, if one occurs.
  class Trace
    getter tag, name

    def initialize(
      @tag : QTag,
      @name : String)
    end

    def to_s(io)
      io << "'" << @name << "' " << "(" << @tag.file << ":" << @tag.line << ")"
    end
  end
end
