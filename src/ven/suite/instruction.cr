module Ven::Suite
  # A bytecode instruction.
  #
  # It can accept an argument, which may be either a label
  # or a data offset pointing to a payload vehicle.
  struct Instruction
    getter line : UInt32
    getter label : Label?
    getter opcode : Opcode
    getter argument : Int32?

    def initialize(@opcode, @argument : Int32?, @line)
    end

    def initialize(@opcode, @label : Label, @line)
    end

    def to_s(io)
      io << @opcode << " " << (@argument || @label)
    end
  end
end
