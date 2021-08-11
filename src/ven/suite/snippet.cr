module Ven::Suite
  # A snippet (known as *basic block* outside of Ven) is a
  # *mutable* collection of `Instruction`s emitted under
  # a `Label`.
  class Snippet
    private alias IArg = Int32 | Label | Nil

    # Returns the instructions in this snippet.
    getter code : Array(Instruction)
    # Returns the label this snippet is emitted under.
    getter label : Label

    def initialize(@label)
      @code = [] of Instruction
    end

    # Appends an instruction with the given *opcode*, *argument*,
    # and *line*, to this snippet.
    def add(opcode : Opcode, argument : IArg, line : Int32)
      @code << Instruction.new(opcode, argument, line)
    end

    # Iterates over this snippet's instructions in groups of
    # size *count*, but advances one instruction at a time.
    # Stops iterating when there are not enough values to
    # make a group of size *count*.
    #
    # Yields the group and the current iteration index to
    # the block.
    def for(count : Int32)
      @code.each_cons(count, reuse: true).with_index do |chunk, start|
        break unless chunk.all?
        yield chunk, start
      end
    end

    # Replaces a range of instructions starting at *start*
    # and of size *count*, with **one** instruction, given
    # its *opcode* and *argument*
    #
    # The line number of the replacee instruction is computed
    # from the line number of the first instruction in the
    # replacement range.
    def replace(start : Int32, count : Int32, opcode : Opcode, argument : IArg)
      unless first = @code[start]?
        raise "Snippet.replace(): snippet not long enough"
      end

      @code[start...start + count] = Instruction.new(opcode, argument, first.line)
    end

    # Removes a range of instructions starting at *start* and
    # of size *count*.
    def remove(start, count : Int32)
      unless @code[start]?
        raise "Snippet.remove(): snippet not long enough"
      end

      @code.delete_at(start...start + count)
    end

    # Returns a snippet with a fictious label.
    def self.core
      new(Label.new)
    end
  end
end
