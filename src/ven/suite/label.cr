module Ven::Suite
  # An *offset reference* to a snippet.
  #
  # Labels are prominent at compile-time, but are replaced
  # with `VJump`s after optimization.
  class Label
    include JSON::Serializable

    # Returns the target snippet of this label, if any.
    property target : Int32?

    def initialize
    end

    def to_s(io)
      io << "(" << (@target || "core") << ")"
    end
  end
end
