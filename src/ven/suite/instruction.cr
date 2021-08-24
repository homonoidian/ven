module Ven::Suite
  # A bytecode instruction.
  #
  # A bytecode instruction may have an argument, which must be
  # either a `Label` or an `Int32`. What this `Int32` means is
  # not of `Instruction`'s concern.
  struct Instruction
    # Returns the line number of the line that produced
    # this instruction.
    getter line : Int32
    # Returns the opcode of this instruction.
    getter opcode : Opcode
    # Returns the label argument of this instruction, if any.
    # `label` and `argument` are mutually exclusive.
    getter label : Label?
    # Returns the Int32 argument of this instruction, if any.
    # `label` and `argument` are mutually exclusive.
    getter argument : Int32?

    def initialize(@opcode, @argument : Int32?, @line)
    end

    def initialize(@opcode, @label : Label, @line)
    end
  end
end
