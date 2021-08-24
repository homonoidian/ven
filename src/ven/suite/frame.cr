module Ven::Suite::MachineSuite
  # A frame is an element of current runtime state.
  class Frame
    # The label of this frame. It can be used to search for
    # particular frames during interpretation.
    enum Label
      Unknown
      Function
    end

    # Returns the label of this frame.
    getter label : Label
    # Returns the trace of this frame, if it was initialized
    # with one.
    getter trace : Trace?

    # Returns the chunk pointer of this frame.
    property cp : Int32
    # Returns the instruction pointer of this frame.
    property ip : Int32 = 0

    # Returns the operand stack (aka stack) of this frame.
    property stack : Models

    # Returns the control stack of this frame.
    #
    # Scheduled for removal.
    property control = [] of Int32

    # The instruction pointer to jump to if there was a death,
    # and it got intercepted by this frame.
    property dies : Int32?

    # The values pushed by `queue`.
    property queue = Models.new

    # The value set by an expression return.
    property returns : Model?

    # An array of failure messages. Used by ensure tests but
    # generic in nature.
    property failures = [] of String

    def initialize(@label = Label::Unknown, @stack = Models.new, @cp = 0, @ip = 0, @trace = nil)
    end

    delegate :last, :last?, to: @stack

    def to_s(io)
      io << "[frame#" << @label << "@" << @cp << ":" << @ip << "]"
    end

    def_clone
  end
end

module Ven::Suite
  include MachineSuite
end
