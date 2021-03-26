module Ven::Suite
  # A reference to a snippet.
  #
  # Note that labels are (and must be) eliminated after
  # optimization. `VJump` payloads are used instead.
  class Label
    property target : Int32?

    def to_s(io)
      io << "(" << (@target || "core") << ")"
    end
  end
end
