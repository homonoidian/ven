module Ven::Suite
  # A chunk is a collection of `Snippet`s.
  class Chunk
    # Returns the filename of the file this chunk was
    # produced from.
    getter file : String
    # Returns the name of this chunk.
    getter name : String

    # Returns the snippets in this chunk.
    getter snippets : Array(Snippet)
    # Returns the instructions in this chunk. Available once
    # this chunk is stitched (see `complete!`)
    getter seamless : Array(Instruction)

    # The payload storages: all jumps, symbols, static data,
    # and functions end up here.
    @jumps = [] of VJump
    @symbols = [] of VSymbol
    @statics = [] of VStatic
    @functions = [] of VFunction

    def initialize(@file, @name)
      @snippets = [Snippet.core]
      @seamless = [] of Instruction
    end

    # These are only used by the `Machine`, and the `Machine`
    # does not (and should not) know anything about snippets.
    # So, redirect to seamless.

    delegate :[], :size, to: @seamless

    # Returns the snippet we currently emit into.
    private macro snippet
      @snippets.last
    end

    # Appends *value* to *target* and returns its index there.
    private macro append(target, value)
      ({{target}} << {{value}}).size - 1
    end

    # Returns the offset of *argument* in the appropriate
    # payload storage. If not found, adds *argument* to the
    # appropriate payload storage first, and then returns
    # the offset.
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

    # Emits an instruction into the current snippet given its
    # *opcode*, *argument* and *line* number.
    def add(opcode : Opcode, argument : Label, line : Int32)
      snippet.add(opcode, argument, line)
    end

    # :ditto:
    def add(opcode, argument, line)
      snippet.add(opcode, offset(argument), line)
    end

    # Declares emission in another snippet. The snippet is
    # created automatically given the *label* (see `Snippet`).
    def label(label : Label)
      @snippets << Snippet.new(label)
      label.target = @snippets.size - 1
    end

    # Returns the `PayloadVehicle` this instruction references,
    # or nil if it doesn't.
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

    # Returns the `PayloadVehicle` this instruction references.
    # Raises if it doesn't.
    def resolve(instruction : Instruction)
      resolve?(instruction) || raise "Chunk.resolve(): #{instruction}"
    end

    # Stitches this chunk.
    #
    # Stitching is the process of merging multiple snippets
    # into one seamless blob.
    #
    # As `Label`s, which reference snippets, lose their meaning
    # with snippets dissolved, their targets are mutated to be
    # the offset of the appropriate snippet's first instruction.
    #
    # Returns true.
    private def stitch
      @snippets.each do |snippet|
        # Idiomatically, labels point to snippets and never
        # to IPs. But we can do anything under the hood!
        snippet.label.target = @seamless.size
        @seamless += snippet.code
      end

      true
    end

    # Replaces all `Label`s in `seamless` with `VJump`s.
    #
    # Returns true.
    private def jumpize
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

    # Stitches and jumpizes this chunk. Use this to make the
    # chunk executable.
    def complete!
      stitch && jumpize

      self
    end

    # Disassembles an *instruction*, assuming this chunk is
    # its context. Prints *index* before the instruction
    # (if specified).
    def to_s(io : IO, instruction : Instruction, index : Int32? = nil)
      argument = resolve?(instruction)

      io << sprintf("%05d", index) << "| " if index
      io << instruction
      io << " (" << argument << ")" if argument
    end

    # Same as `to_s(io, instruction)`.
    def to_s(instruction : Instruction, index : Int32? = nil)
      String.build { |io| to_s(io, instruction, index) }
    end

    # Disassembles `seamless` if available, otherwise `snippets`.
    def to_s(io : IO, deepen = 2)
      io << @name << " {\n"

      if !@seamless.empty?
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

    # Disassembles this chunk given no IO (see `to_s(io)`)
    def to_s
      String.build { |io| to_s(io) }
    end
  end

  alias Chunks = Array(Chunk)
end
