module Ven::Suite
  # A frame is a package of state. It is there to simplify
  # statekeeping. For an instance of `Machine`, it provides:
  #
  # - A chunk pointer (chunk index, really)
  # - An instruction pointer (instruction index, really)
  # - An operand stack (or just stack)
  # - A control stack (used, say, to save iteration indices)
  # - An underscores stack (used for context, i.e., '_' and '&_')
  # - A Goal (`Frame::Goal`): what the Machine is  trying to
  # achieve with this frame.
  class Frame
    # The goal of this frame. It represents the reason this
    # frame was created in the first place.
    enum Goal
      # The goal of this frame is unknown.
      Unknown

      # This frame was created in order to evaluate a function.
      Function
    end

    getter goal : Goal

    property cp : Int32
    property ip : Int32 = 0

    property stack : Models
    property control = [] of Int32
    property underscores = Models.new

    # The IP to jump if there was a death.
    property dies : Int32?

    def initialize(@goal = Goal::Unknown, @stack = Models.new, @cp = 0)
    end

    delegate :last, :last?, to: @stack

    def to_s(io)
      io << "frame@" << @cp << " [goal: " << goal << "] {\n"
      io << "  ip: " << @ip << "\n"
      io << "  oS: " << @stack.join(" ") << "\n"
      io << "  cS: " << @control.join(" ")  << "\n"
      io << "  _S: " << @underscores.join(" ")  << "\n"
    end
  end
end
