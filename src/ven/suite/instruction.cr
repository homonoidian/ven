module Ven::Suite
  # An individual bytecode instruction.
  #
  # Instructions are aware of the chunk they are in (through
  # the chunk hash) and of their own position in this chunk.
  # This is so to make each instruction unique.
  struct Instruction
    getter line : UInt32
    getter index : Int32
    getter label : Label?
    getter offset : Int32?
    getter opcode : Symbol


    def initialize(@index, @opcode, @label : Label?, @line)
    end

    def initialize(@index, @opcode, @offset : Int32, @line)
    end

    def to_s(io)
      io << sprintf("%05d", @index) << "| " << @opcode << " " << (@offset || @label)
    end
  end
end
