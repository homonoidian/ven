module Ven::Suite
  # An offset reference to a snippet (called target).
  #
  # Note that labels are (and must be) replaced with `VJump`s
  # after optimization.
  class Label
    property target : Int32?

    def to_s(io)
      io << "(" << (@target || "core") << ")"
    end
  end
end
