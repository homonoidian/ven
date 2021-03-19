module Ven::Suite
  # Frame encapsualtes all that is relevant to the current
  # state of a `Machine`.
  class Frame
    property cp : Int32
    property ip : Int32 = 0
    property stack : Models
    property control = [] of Int32
    property underscores = Models.new

    def initialize(@stack = Models.new, @cp = 0)
    end

    delegate :last, :last?, to: @stack

    def to_s(io)
      io << "S = " << @stack.join(" ") << ";\n"
      io << "C = " << @control.join(" ") << ";\n"
      io << "_ = " << @underscores.join(" ") << ";\n"
    end
  end
end
