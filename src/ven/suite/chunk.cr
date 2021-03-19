require "big"

module Ven::Suite
  # A chunk is a blob of instructions, static data and, in
  # some cases, metadata.
  class Chunk
    # The various types of data this chunk can carry along.
    alias Data = Int32 | String | BigDecimal | Entry

    getter file : String
    getter name : String
    getter meta : Metadata::Meta
    getter data = [] of Data
    getter code = [] of Instruction

    def initialize(@file, @name, @meta = Metadata::Empty.new)
      @index = 0
      @label = {} of Label => Int32
    end

    delegate :[], :size, to: @code

    # Appends an offset instruction to the list of this chunk's
    # instructions.
    #
    # If this chunk's data already includes *data*, the existing
    # value is referenced. Otherwise, *data* is appended to
    # this chunk's data first, and only then referenced.
    #
    # Returns true.
    def add(line : UInt32, opcode : Symbol, data : Data? = nil)
      if data
        existing = @data.index do |entity|
          true if entity.class == data.class && entity == data
        end

        offset = existing || (@data << data).size - 1
      end

      @code << Instruction.new(
        @index,
        opcode,
        offset,
        line)

      @index += 1

      true
    end

    # Appends a label instruction to the list of this chunk's
    # instructions.
    #
    # Returns true.
    def add(line : UInt32, opcode : Symbol, label : Label)
      @code << Instruction.new(
        @index,
        opcode,
        label,
        line)

      @index += 1

      true
    end

    # Declares *label* at the emission offset.
    #
    # Returns true.
    def label(label : Label)
      @label[label] = @code.size

      true
    end

    # Resolves all labels in this chunk.
    #
    # Returns true.
    def delabel
      @code.each_with_index do |instruction, index|
        label = instruction.label || next

        unless anchor = @label[label]?
          raise "this label was never declared: #{label}"
        end

        @code[index] = Instruction.new(
          instruction.index,
          instruction.opcode,
          anchor,
          instruction.line)
      end

      true
    end

    # Tries to resolve the argument of an *instruction* off
    # this chunk's data.
    #
    # Returns the referencee if succeeded, or nil if did not.
    def resolve(instruction : Instruction)
      if offset = instruction.offset
        @data[offset]
      end
    end

    def to_s(instruction : Instruction, indent = 0)
      String.build do |str|
        str << " " * indent << instruction

        if references = resolve(instruction)
          str << " (" << references << ")"
        end
      end
    end

    def to_s(io, indent = 2)
      io << @name << " [" << hash << "]:\n"

      @code.each do |instruction|
        io << to_s(instruction, indent) << "\n"
      end
    end
  end

  alias Chunks = Array(Chunk)
end
