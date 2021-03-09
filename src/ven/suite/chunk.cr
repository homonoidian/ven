module Ven::Suite
  # Represents a single instruction.
  struct Instruction
    getter line : UInt32
    getter opcode : Symbol
    getter offset : Int32?

    def initialize(@opcode, @offset, @line)
    end

    def to_s(io)
      io << "(" << @line << ")" << " " << @opcode

      unless @offset.nil?
        io << " " << @offset
      end
    end
  end

  # A container for instructions and the data that they use.
  class Chunk
    alias Data = String | Int32

    getter file : String
    getter data : Array(Data)
    getter code : Array(Instruction)

    def initialize(@file)
      @data = [] of Data
      @code = [] of Instruction
    end

    delegate :[], :size, to: @code

    # Pops *amount* instructions. Returns the list of popped
    # instructions, **reversed** (so it can be properly 'plugged
    # in' again.)
    def take(amount : Int32)
      took = [] of Instruction

      amount.times do
        took << @code.pop
      end

      took.reverse
    end

    # Concatenates this Chunk's instructions with an Array of
    # *other* instructions.
    def <<(other : Array(Instruction))
      @code += other
    end

    # Adds a new instruction to this chunk. *opcode* is the
    # opcode of this instruction, and *argument* is its argument.
    # Note that the data offset for the argument is computed
    # automatically.
    def add(line : UInt32, opcode : Symbol, argument : Data? = nil)
      unless argument.nil?
        offset = @data.index(&.== argument) || (@data << argument).size - 1
      end

      @code << Instruction.new(opcode, offset, line)
    end

    # Resolves the argument of an *instruction* based on the
    # data of this chunk. Returns nil if the *instruction*
    # has no data offset, or data is not long enough, To resolve
    # an argument means to return the value an instruction's
    # data offset points to.
    def resolve(instruction : Instruction) : Data?
      if offset = instruction.offset
        @data[offset]?
      end
    end

    def to_s(io)
      @code.each_with_index do |instruction, index|
        io << index << "| " << instruction

        if offset = instruction.offset
          io << " :: "

          @data[offset].inspect(io)
        end

        io << "\n"
      end
    end
  end

  alias Chunks = Array(Chunk)
end
