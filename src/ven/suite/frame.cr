module Ven::Suite
  # A frame is simply some packed state. It is there to make
  # statekeeping trivial for the `Machine`.
  class Frame
    # Represents why this frame was created.
    enum Goal
      Unknown

      # If created to evaluate a function:
      Function
    end

    getter goal : Goal

    property cp : Int32
    property ip : Int32 = 0

    property stack : Models
    property control = [] of Int32
    property underscores = Models.new

    # The IP to jump if there was a death in or under this
    # frame.
    property dies : Int32?

    # The model that this frame will return on `RET`.
    property returns : Model?

    def initialize(@goal = Goal::Unknown, @stack = Models.new, @cp = 0)
    end

    delegate :last, :last?, to: @stack

    def to_s(io)
      io << "frame@" << @cp << " [goal: " << goal << "]\n"
      io << "  ip: " << @ip << "\n"
      io << "  oS: " << @stack.join(" ") << "\n"
      io << "  cS: " << @control.join(" ")  << "\n"
      io << "  _S: " << @underscores.join(" ")  << "\n"
      io << "   R: " << @returns << "\n"
      io << "   D: " << @dies << "\n"
    end
  end
end
