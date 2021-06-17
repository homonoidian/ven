module Ven::Suite
  # A bytecode instruction.
  #
  # A bytecode instruction may accept an argument, which must
  # be either a `Label` or an integer. What this integer means
  # is not of Instruction's concern.
  struct Instruction
    include JSON::Serializable

    getter line : Int32
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
