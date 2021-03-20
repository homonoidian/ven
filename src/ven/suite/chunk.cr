require "big"

module Ven::Suite
  # Represents a static data argument.
  alias DStatic = Int32 | BigDecimal | String

  # Represents a symbolic argument with some *name* and *nesting*.
  struct DSymbol
    getter name : String
    getter nesting : Int32

    def initialize(@name, @nesting)
    end

    def to_s(io)
      io << "symbol " << @name << "#" << @nesting
    end
  end

  # Represents a jump to some instruction pointer.
  #
  # The compiler inserts it automatically at `delabel` stage.
  # There is no need to use DJump explicitly.
  struct DJump
    getter anchor : Int32

    def initialize(@anchor)
    end

    def to_s(io)
      io << "to " << @anchor
    end
  end

  # Represents a function argument.
  class DFunction
    getter name : String

    property chunk : Int32
    property given : Int32
    property arity : Int32
    property slurpy : Bool
    property params : Array(String)

    def initialize(@name)
      @chunk = uninitialized Int32
      @given = uninitialized Int32
      @arity = uninitialized Int32
      @slurpy = uninitialized Bool
      @params = uninitialized Array(String)
    end

    def to_s(io)
      io << "fun " << @name << "@" << @chunk
    end
  end

  # A chunk is a blob of instructions, static data, symbols
  # and functions.
  class Chunk
    # Records which opcode takes what kind of argument.
    @@takes = {} of Symbol => Symbol

    getter file : String
    getter name : String

    getter code : Array(Instruction)
    getter jumps : Array(DJump)
    getter static : Array(DStatic)
    getter symbols : Array(DSymbol)
    getter functions : Array(DFunction)

    @index = 0

    def initialize(@file, @name)
      @code = [] of Instruction
      @label = {} of Label => Int32
      @jumps = [] of DJump
      @static = [] of DStatic
      @symbols = [] of DSymbol
      @functions = [] of DFunction
    end

    delegate :[], :size, to: @code

    # Returns the offset of an *argument* in a *container*.
    private def offset?(argument : DStatic, in container : Array(DStatic))
      found = container.index do |item|
        argument.class == item.class && item == argument
      end

      unless found
        container << argument
      end

      found || container.size - 1
    end

    # :ditto:
    private def offset?(argument : T, in container : Array(T)) forall T
      container.index(argument) || (container << argument).size - 1
    end

    # Appends an instruction and increments the index counter.
    #
    # Returns true.
    private def add!(opcode : Symbol, offset : Int32?, line : UInt32)
      @code << Instruction.new(@index, opcode, offset, line)
      @index += 1

      true
    end

    # :ditto:
    private def add!(opcode, label : Label, line)
      @code << Instruction.new(@index, opcode, label, line)
      @index += 1

      true
    end

    # Appends an argumentless instruction.
    def add(opcode : Symbol, argument : Nil, line : UInt32)
      add!(opcode, nil, line)
    end

    # Appends an instruction whose *argument* is `DStatic`.
    #
    # Saves *argument* in this chunk's statics, if not there
    # already.
    def add(opcode, argument : DStatic, line)
      @@takes[opcode] = :static

      add!(opcode, offset?(argument, in: @static), line)
    end

    # Appends an instruction whose *argument* is `DSymbol`.
    #
    # Saves *argument* in this chunk's symbols, if not there
    # already.
    def add(opcode, argument : DSymbol, line)
      @@takes[opcode] = :symbol

      add!(opcode, offset?(argument, in: @symbols), line)
    end

    # Appends an instruction whose *argument* is `DFunction`.
    #
    # Saves *argument* in this chunk's functions, if not there
    # already.
    def add(opcode, argument : DFunction, line)
      @@takes[opcode] = :function

      add!(opcode, offset?(argument, in: @functions), line)
    end

    # Appends an instruction whose  *argument* is `Label`.
    def add(opcode, argument : Label, line)
      @@takes[opcode] = :jump

      add!(opcode, argument, line)
    end

    # Declares *label* at the emission offset.
    #
    # Returns true.
    def label(label : Label)
      @label[label] = @code.size

      true
    end

    # Resolves the labels in this chunk.
    #
    # Returns true.
    def delabel
      @code.each_with_index do |instruction, index|
        label = instruction.label || next

        unless anchor = @label[label]?
          raise "this label was never declared: #{label}"
        end

        jump_offset = offset?(DJump.new(anchor), in: @jumps)

        @code[index] =
          Instruction.new(
            instruction.index,
            instruction.opcode,
            jump_offset,
            instruction.line)
      end

      true
    end

    # Tries to resolve the argument of an *instruction* off
    # this chunk's static data, symbols or functions.
    #
    # Returns the referencee if succeeded, or nil if did not.
    def resolve(instruction : Instruction, kind = :static)
      if offset = instruction.argument
        case kind
        when :jump
          @jumps[offset]
        when :static
          @static[offset]
        when :symbol
          @symbols[offset]
        when :function
          @functions[offset]
        else
          raise "malformed resolve() kind"
        end
      end
    end

    # Disassembles an *instruction*. If *point* is true,
    # prepends the disassembly with `>>>`.
    def dis(instruction : Instruction, point = false)
      String.build do |str|
        str << (point ? ">>> #{instruction}" : instruction)

        if kind = @@takes[instruction.opcode]?
          str << " (" << resolve(instruction, kind) << ")"
        end
      end
    end

    # Disassembles whole chunk. If *point_at* is provided,
    # `>>>` is going to be printed before the correspoding
    # instruction.
    def dis(point_at : Int32? = nil)
      String.build do |str|
        str << @name << ":\n"

        @code.each_with_index do |instruction, index|
          str << dis(instruction, point_at == index) << "\n"
        end
      end
    end

    def to_s(io)
      io << dis
    end
  end

  alias Chunks = Array(Chunk)
end
