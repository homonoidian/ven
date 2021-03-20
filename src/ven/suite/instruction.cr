module Ven::Suite
  # An individual bytecode instruction.
  struct Instruction
    getter line : UInt32
    getter index : Int32
    getter label : Label?
    getter opcode : Symbol
    getter argument : Int32?

    def initialize(@index, @opcode, @label : Label?, @line)
    end

    def initialize(@index, @opcode, @argument : Int32, @line)
    end

    def to_s(io)
      io << sprintf("%05d", @index) << "| " << @opcode << " " << (@argument || @label)
    end
  end
end
