module Ven::Suite::MachineSuite
  # An *offset reference* to a snippet.
  #
  # Labels are prominent at compile-time, but are replaced
  # with `VJump`s after optimization.
  class Label
    # Returns the target snippet of this label, if any.
    property target : Int32?

    def initialize
    end

    def to_s(io)
      io << "(" << (@target || "core") << ")"
    end
  end
end

module Ven::Suite
  include MachineSuite
end
