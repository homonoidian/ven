module Ven::Suite
  # A reference to an instruction pointer.
  class Label
    property target : Int32?

    def to_s(io)
      io << "(" << (@target || "core") << ")"
    end
  end
end
