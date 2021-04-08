module Ven::Suite
  # A frame is simply some packed state. It is there to make
  # statekeeping trivial for the `Machine`.
  class Frame
    # The reason this frame was created.
    enum Goal
      Unknown
      Function
    end

    getter goal : Goal

    # Chunk pointer, a reference to the chunk this frame executes.
    property cp : Int32
    property ip : Int32 = 0

    property stack : Models
    property control = [] of Int32
    property underscores = Models.new

    # The instruction pointer to jump to if there was a death
    # in or under this frame.
    property dies : Int32?

    # The model that will be returned if everything goes
    # according to plan.
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
