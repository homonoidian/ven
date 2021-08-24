module Ven::Suite
  # `Dis` can disassemble `Snippet`s, `Chunk`s, and `Instruction`s
  # in a modular way. It lets you choose how they are formatted (or
  # just tweak the default formatting), and where the disassembly
  # gets written to.
  #
  # Basic usage:
  #
  # ```
  # Dis.dis(chunk : Chunk) : String
  # # These are not recommended, since they disable parts of
  # # `FormatContext` some formatters may depend on.
  # Dis.dis(snippet : Snippet) : String
  # Dis.dis(instruction : Instruction) : String
  # ```
  #
  # You can provide a custom format object instance. It must
  # inherit `Dis::IFormat`, or any of its subclasses:
  #
  # ```
  # Dis.dis(chunk : Chunk, MyFormat.new) : String
  # ```
  #
  # See `Dis::DefaultFormat` for an example of how to subclass
  # an `IFormat`.
  #
  # With an IO:
  #
  # ```
  # Dis.new(io : IO).dis(chunk : Chunk) : Nil
  # ```
  class Dis
    # The amount of spaces in an indentation.
    INDENT = 2

    # Represents a format context.
    #
    # The format context is especially useful in the methods
    # of `IFormat`. It can be used to gather the necessary
    # information for the format string.
    record FormatContext, ip = nil, chunk = nil, snippet = nil, instruction = nil do
      # Returns the current instruction pointer.
      getter! ip : Int32
      # Returns the current chunk.
      getter! chunk : Chunk
      # Returns the current snippet.
      getter! snippet : Snippet
      # Returns the current instruction.
      getter! instruction : Instruction
    end

    # An interface that all Dis formatters must conform to.
    #
    # By implementing it, you will have control over everything
    # except newlines, spaces, and indentation in the resulting
    # disassembly.
    abstract class IFormat
      # Appends an instruction pointer to *io*.
      abstract def on_ip(io, ctx : FormatContext)
      # Appends an instruction opcode to *io*.
      abstract def on_opcode(io, ctx : FormatContext)
      # Appends an instruction argument to *io*.
      abstract def on_argument(io, ctx : FormatContext)
      # Appends a chunk head (which is put before the indented
      # body of a chunk, no matter if it is a stitched chunk,
      # or an unstitched chunk) to *io*.
      abstract def on_chunk_head(io, ctx : FormatContext)
      # Appends a snippet label to *io*.
      abstract def on_snippet_label(io, ctx : FormatContext)
    end

    # The default implementation of the `IFormat` interface.
    #
    # You can inherit from this implementation to decorate its
    # output, calling the appropriate supermethods wherever
    # appropriate. Do remember, though, that the supermethods
    # *append* to the *io* argument, and return Nil.
    #
    # ```
    # class MyFormat < DefaultFormat
    #   def on_ip(io, ctx)
    #     Colorize.with.dark_gray.surround(io) do
    #       super
    #     end
    #   end
    # end
    # ```
    class DefaultFormat < IFormat
      def on_ip(io, ctx)
        io << sprintf("%05d| ", ctx.ip)
      end

      def on_opcode(io, ctx)
        io << ctx.instruction.opcode
      end

      def on_argument(io, ctx)
        ins = ctx.instruction

        if ins.label
          io << " " << ins.label
        elsif ins.argument
          io << ctx.chunk.resolve(ins)
        end
      end

      def on_chunk_head(io, ctx)
        io << sprintf("[chunk '%s' in %s]", ctx.chunk.name, ctx.chunk.file)
      end

      def on_snippet_label(io, ctx)
        io << sprintf("%s:", ctx.snippet.label)
      end
    end

    @indent = 0

    # Initializes this disassembler with an *io* to write to,
    # and an object that implements the `IFormat` interface.
    def initialize(@io : IO, @fmt : IFormat = DefaultFormat.new)
    end

    # Writes `INDENT` spaces of indentation to the IO, and
    # yields. Any calls to this method in the block would
    # take the new indentation level into account.
    private def indent
      @indent += INDENT

      # Prepend the leading indentation, for the first thing
      # that is inserted into the IO.
      @io << " " * @indent

      yield

      @indent -= INDENT
    end

    # Writes *object* to the IO.
    @[AlwaysInline]
    private def write(object : String)
      @io << object
    end

    # Noop for uniformity.
    @[AlwaysInline]
    private def write(object)
    end

    # Disassembles the given *instruction* into the IO, using
    # the format object of this disassembler.
    #
    # Returns nil.
    def dis(ctx, instruction : Instruction) : Nil
      ctx = ctx.copy_with(instruction: instruction)

      write @fmt.on_opcode(@io, ctx)

      # `on_argument` may be concerned with something other
      # than the argument if the instruction doesn't have
      # one, so we can only cut this space out.
      write " " if instruction.argument

      write @fmt.on_argument(@io, ctx)
    end

    # Disassembles the given *snippet* into the IO, using the
    # format object of this disassembler.
    #
    # Returns nil.
    def dis(ctx, snippet : Snippet) : Nil
      ctx = ctx.copy_with(snippet: snippet)

      write @fmt.on_snippet_label(@io, ctx)
      write "\n"

      snippet.code.each_with_index do |instruction, index|
        ctx = ctx.copy_with(ip: index, instruction: instruction)

        indent do
          write @fmt.on_ip(@io, ctx)
          write dis(ctx, instruction)
          write "\n"
        end
      end
    end

    # Disassembles the given *chunk* into the IO, using the
    # format object of this disassembler.
    #
    # If *chunk* is stitched, disassembles it as a stitched
    # chunk. If *chunk* is unstitched, disassembles it as an
    # unstitched chunk.
    #
    # Returns nil.
    def dis(ctx, chunk : Chunk) : Nil
      ctx = ctx.copy_with(chunk: chunk)

      write @fmt.on_chunk_head(@io, ctx)
      write "\n"

      if chunk.seamless.empty?
        # Which means it's unstitched.
        chunk.snippets.each do |snippet|
          indent do
            write dis(ctx, snippet)
          end
        end
      else
        # Which means it's stitched.
        chunk.seamless.each_with_index do |instruction, index|
          ctx = ctx.copy_with(ip: index, instruction: instruction)

          indent do
            write @fmt.on_ip(@io, ctx)
            write dis(ctx, instruction)
            write "\n"
          end
        end
      end
    end

    # Disassembles *object*.
    #
    # Look at the other instance-side `dis` methods to see
    # what kinds of *object*s can be disassembled.
    #
    # By agreement, this is the only public instance-side
    # method of `Dis`.
    def dis(object) : Nil
      dis(FormatContext.new, object)
    end

    # Disassembles *object*.
    #
    # Look at the instance-side `dis` methods to see what kinds
    # of *object*s can be disassembled.
    #
    # Look at `IFormat`, `DefaultFormat`, and `new` to learn
    # what *fmt* is, and how you can use it.
    def self.dis(object, fmt : IFormat = DefaultFormat.new)
      String.build do |io|
        new(io, fmt).dis(object)
      end
    end
  end
end
