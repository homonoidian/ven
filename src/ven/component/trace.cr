module Ven::Component
  # The trace a capsule (see `Context.local`) leaves while
  # being evaluated.
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
