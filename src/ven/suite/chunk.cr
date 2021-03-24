module Ven::Suite
  # A chunk is an abstraction over a collection of `Snippet`s.
  class Chunk
    getter file : String
    getter name : String

    getter snippets
    getter seamless

    # The payload storages of this chunk: all jumps, symbols,
    # static data and functions end up here.
    @jumps = [] of VJump
    @symbols = [] of VSymbol
    @statics = [] of VStatic
    @functions = [] of VFunction

    def initialize(@file, @name)
      @snippets = [Snippet.core]
      @seamless = [] of Instruction
    end

    # These are only used by the Machine, and the Machine does
    # not (and should not) know anything about snippets. So,
    # redirect to seamless.
    delegate :[], :size, to: @seamless

    # Returns the snippet we currently emit to.
    private macro snippet
      @snippets.last
    end

    # Appends *value* to *target* and returns its index there.
    private macro append(target, value)
      ({{target}} << {{value}}).size - 1
    end

    # Returns the offset of *argument* in the appropriate
    # payload storage, if it is there already. Otherwise,
    # adds *argument* to the appropriate payload storage
    # first, and then returns the resulting offset.
    def offset(argument : VJump)
      @jumps.index(argument) || append(@jumps, argument)
    end

    # :ditto:
    def offset(argument : VStatic)
      @statics.index(argument) || append(@statics, argument)
    end

    # :ditto:
    def offset(argument : VSymbol)
      @symbols.index(argument) || append(@symbols, argument)
    end

    # :ditto:
    def offset(argument : VFunction)
      @functions.index(argument) || append(@functions, argument)
    end

    # :ditto:
    def offset(argument : Static)
      offset VStatic.new(argument)
    end

    # :ditto:
    def offset(argument : Nil)
      nil
    end

    # Appends an instruction given its *opcode*, *argument*
    # and *line* number.
    def add(opcode : Opcode, argument : Payload, line : UInt32)
      snippet.add(opcode, offset(argument), line)
    end

    # :ditto:
    def add(opcode, argument : Label, line)
      snippet.add(opcode, argument, line)
    end

    # :ditto:
    def add(opcode, argument, line)
      snippet.add(opcode, offset(argument), line)
    end

    # Declares that whatever follows should be emitted under
    # the label *label*.
    def label(label : Label)
      @snippets << Snippet.new(label)
      label.target = @snippets.size - 1
    end

    # Returns the payload vehicle this instruction references,
    # or nil if it doesn't reference one.
    def resolve?(instruction : Instruction)
      return nil unless argument = instruction.argument

      case instruction.opcode.payload
      when :jump
        @jumps[argument]
      when :static
        @statics[argument]
      when :symbol
        @symbols[argument]
      when :function
        @functions[argument]
      end
    end

    # Returns the payload vehicle this instruction references.
    # Raises if it doesn't reference one.
    def resolve(instruction : Instruction)
      resolve?(instruction) || raise "Chunk.resolve(): #{instruction}"
    end

    # Stitches this chunk.
    #
    # Stitching is the process of merging many snippets of
    # instructions into one seamless blob.
    #
    # As labels that reference snippets lose their meaning
    # with no snippets there, the references to snippets are
    # changed to the offsets of snippets' first instructions.
    #
    # Returns true.
    def stitch
      @snippets.each do |snippet|
        snippet.label.target = @seamless.size
        @seamless += snippet.code
      end

      true
    end

    # Replaces all labels in seamless with the appropriate
    # jumps (see `VJump`).
    #
    # Returns true.
    def jumpize
      @seamless.map! do |instruction|
        line, opcode = instruction.line, instruction.opcode

        if target = instruction.label.try(&.target)
          Instruction.new(opcode, offset(VJump.new target), line)
        else
          Instruction.new(opcode, instruction.argument, line)
        end
      end

      true
    end

    # Stitches and jumpizes this chunk.
    def complete!
      stitch && jumpize

      self
    end

    # Disassembles an *instruction*, trying to resolve its
    # argument with the payload storage of this chunk. If
    # got an *index*, prints it before the instruction.
    def to_s(io : IO, instruction : Instruction, index : Int32? = nil)
      argument = resolve?(instruction)

      io << sprintf("%05d", index) << "| " if index
      io << instruction
      io << " (" << argument << ")" if argument
    end

    # Disassembles seamless if available, otherwise snippets.
    def to_s(io : IO, deepen = 2)
      io << @name << " {\n"

      unless @seamless.empty?
        @seamless.each_with_index do |instruction, index|
          io << " " * deepen; to_s(io, instruction, index); io << "\n"
        end
      else
        @snippets.each do |snippet|
          io << " " * deepen << snippet.label << ":\n"

          snippet.code.each do |instruction|
            io << " " * (deepen * 2); to_s(io, instruction); io << "\n"
          end
        end
      end

      io << "}\n"
    end

    # Disassembles an *instruction* given no IO (see `to_s(io, instruction)`).
    def to_s(instruction : Instruction, index : Int32? = nil)
      String.build { |io| to_s(io, instruction, index) }
    end

    # Disassembles this chunk given no IO (see `to_s(io)`)
    def to_s
      String.build { |io| to_s(io) }
    end
  end

  alias Chunks = Array(Chunk)
end
