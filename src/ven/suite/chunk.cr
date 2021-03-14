module Ven::Suite
  # Represents a unique label.
  class Label
    def to_s(io)
      io << hash
    end
  end

  # Represents a single instruction.
  struct Instruction
    getter line : UInt32
    getter label : Label?
    getter offset : Int32?
    getter opcode : Symbol

    def initialize(@opcode, argument : Nil, @line)
    end

    def initialize(@opcode, argument : Label, @line)
      @label = argument
    end

    def initialize(@opcode, argument : Int32, @line)
      @offset = argument
    end

    def to_s(io)
      io << "(" << @line << ")" << " " << @opcode

      if !@offset.nil?
        io << " " << @offset
      elsif !@label.nil?
        io << " (unresolved label)" << @label
      end
    end
  end

  # A container for instructions and the data they reference.
  class Chunk
    private alias Data = String | Int32
    private alias Meta = Array(String) | Data | Bool

    getter file : String
    getter name : String
    getter data : Array(Data)
    getter code : Array(Instruction)
    getter meta : Hash(Symbol, Meta)

    def initialize(@file, @name)
      @data = [] of Data
      @code = [] of Instruction
      @meta = {} of Symbol => Meta
      @label = {} of Label => Int32
    end

    delegate :[], :size, to: @code
    delegate :[]=, to: @meta

    # Appends a new `Instruction` to the list of this chunk's
    # instructions. If this chunk's data already includes the
    # *argument*, the existing value is referenced. Otherwise,
    # *argument* is appended to this chunk's data first, and
    # only then referenced. *index* is the index in `@code`
    # where the new instruction will reside. Returns true.
    def add(line : UInt32, opcode : Symbol, argument : Data? = nil, index = nil)
      unless argument.nil?
        offset = @data.index(&.== argument) || (@data << argument).size - 1
      end

      # *offset* is nil if no *argument*
      if index
        @code[index] = Instruction.new(opcode, offset, line)
      else
        @code << Instruction.new(opcode, offset, line)
      end

      true
    end

    # Appends a new `Instruction` to the list of this chunk's
    # instructions. *label* is the `Label` this instruction
    # references. Returns true.
    def add(line : UInt32, opcode : Symbol, label : Label)
      @code << Instruction.new(opcode, label, line)

      true
    end

    # Declares a new `Label`, *label*, at the emission offset.
    # Returns true.
    def label(label : Label)
      @label[label] = @code.size

      true
    end

    # Resolves the labels in this chunk. Returns true.
    def delabel
      @code.each_with_index do |instruction, index|
        if label = instruction.label
          unless anchor = @label[label]?
            raise "label never declared: #{label}"
          end

          add(instruction.line, instruction.opcode, anchor, index)
        end
      end

      true
    end

    # Resolves the argument of an *instruction* using the data
    # of this chunk. Returns nil if the *instruction* does not
    # reference any data, or if the data it references does
    # not exist.
    def resolve(instruction : Instruction) : Data?
      if offset = instruction.offset
        @data[offset]?
      end
    end

    def to_s(io)
      io << @name << ":\n"

      @code.each_with_index do |instruction, index|
        io << index << "| " << instruction

        if data = resolve(instruction)
          io << " ("; data.inspect(io); io << ")"
        end

        io << "\n"
      end
    end
  end

  alias Chunks = Array(Chunk)
end
