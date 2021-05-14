module Ven::Suite
  # A snippet is a mutable collection of instructions emitted
  # under one label.
  class Snippet
    alias IArg = Int32 | Label | Nil

    getter code : Array(Instruction)
    getter label : Label

    def initialize(@label)
      @code = [] of Instruction
    end

    # Adds to this chunk an instruction with the given *opcode*,
    # *argument* and *line*.
    def add(opcode : Opcode, argument : IArg, line : Int32)
      @code << Instruction.new(opcode, argument, line)
    end

    # Iterates over this snippet's instructions in chunks of
    # size *count*, but advances one instruction at a time.
    # Stops iterating when there are not enough values to
    # make a full chunk.
    #
    # Yields the chunk and the current iteration index to
    # the block.
    def for(count : Int32)
      @code.each_cons(count, reuse: true).with_index do |chunk, start|
        break unless chunk.all?

        yield chunk, start
      end
    end

    # Replaces a blob of instructions starting at *start* and
    # of size *count* with **one** instruction, given its
    # *opcode* and *argument*
    #
    # The line number of the replacee instruction is computed
    # from the line number of the first instruction in the
    # blob-to-replace.
    def replace(start : Int32, count : Int32, opcode : Opcode, argument : IArg)
      unless first = @code[start]?
        raise "Snippet.replace(): snippet not long enough"
      end

      @code[start...start + count] =
        Instruction.new(
          opcode,
          argument,
          first.line)
    end

    # Removes a blob of instructions starting at *start* and
    # of size *count*.
    def remove(start, count : Int32)
      unless first = @code[start]?
        raise "Snippet.replace(): snippet not long enough"
      end

      @code.delete_at(start...start + count)
    end

    # Returns a new snippet with a fictious label.
    def self.core
      new(Label.new)
    end
  end
end
