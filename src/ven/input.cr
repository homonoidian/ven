module Ven
  alias Distinct = Array(String)

  # An abstraction over a Ven file, and one of the highest
  # Ven abstractions overall.
  #
  # Implements common context. This means that any new input
  # is evaluated in the same context where all other inputs
  # were evaluated.
  #
  # ```
  # foo = Ven::Input.new("foo", "x = 2 + 2")
  # bar = Ven::Input.new("bar", "x + 1")
  #
  # puts foo.run # ==> 4 : Num
  # puts bar.run # ==> 5 : Num
  # ```
  struct Input
    include Suite

    @@chunks = Chunks.new
    @@reader = Reader.new
    @@context = Context::Hub.new

    getter file : String
    getter source : String

    getter exposes = [] of Distinct
    getter distinct : Distinct?

    # Whether to print the quote tree after reading.
    property tree = false

    # See `Machine.measure`.
    property measure = false

    # See `Machine.inspect`.
    property inspect = false

    # Whether to only display the tree.
    property tree_only = false

    # Whether to print the disassembled chunks.
    property disassemble = false

    @quotes = Quotes.new

    def initialize(@file, @source)
      @@context.extend(Library::Internal.new)

      # Pre-read, once.
      read
    end

    # Returns the class-level (aka common, super-Input)
    # context hub (see `Context::Hub`).
    def self.context
      @@context
    end

    # Reads this input and passes each consequtive quote to
    # the block.
    private def quotes
      @@reader.read(@file, @source) do |quote|
        yield quote
      end
    end

    # Reads this input, caching each consequtive quote.
    #
    # Fills the `distinct` and `expose` of this input in case
    # this quote is a distinct statement or an expose statement,
    # correspondingly.
    private def read
      quotes do |quote|
        if quote.is_a?(QDistinct)
          @distinct = quote.pieces
        elsif quote.is_a?(QExpose)
          @exposes << quote.pieces
        end

        @quotes << quote
      end
    end

    # Reads and compiles the resulting quotes into chunks,
    # which are then returned.
    #
    # The compiler will emit chunks with cross-chunk references
    # respecting the *offset*.
    #
    # Respects `disassemble`.
    private macro chunkize(offset)
      %compiler = Compiler.new(@@context.compiler, @file, {{offset}})

      @quotes.each do |%quote|
        %compiler.visit(%quote)
      end

      if @disassemble
        puts "[pre-optimize disassembly]".colorize(:blue)

        %compiler.result.each do |chunk|
          puts chunk
        end
      end

      %compiler.result
    end

    # Optimizes the *chunks*, with *passes* being the desired
    # amount of optimization passes.
    #
    # Returns the chunks back.
    private macro optimize(chunks, passes)
      %optimizer = Optimizer.new(%chunks = {{chunks}})
      %optimizer.optimize({{passes}})
      %chunks
    end

    # Completes the *chunks* by calling `complete!` on every
    # one of them, and contributes the completed chunks to
    # the list of common chunks (`@@chunks`).
    #
    # Respects `disassemble`.
    private macro complete(chunks)
      %chunks = {{chunks}}
      %chunks.each(&.complete!)

      if @disassemble
        puts "[post-optimize disassembly]".colorize(:blue)

        %chunks.each do |chunk|
          puts chunk
        end
      end

      @@chunks += %chunks
    end

    # Goes through the full pipeline of compilation. See macros
    # `chunkize`, `optimize`, `complete`.
    private macro compile(offset, passes)
      complete optimize(chunkize({{offset}}), {{passes}})
    end

    # Evaluates the chunks (i.e., `@@chunks`) starting at
    # *offset*. Returns the result of the evaluation.
    private macro evaluate(offset)
      %machine = Machine.new(@@context.machine, @@chunks, {{offset}})

      %machine.measure = @measure
      %machine.inspect = @inspect

      %machine.start

      if @measure
        puts "[measure]".colorize(:blue)

        %machine.timetable.each do |cp, stats|
          puts "chunk at #{cp} {"

          stats.each do |ip, stat|
            amount = stat[:amount]
            duration = stat[:duration]
            instruction = stat[:instruction]

            took = "#{duration.microseconds}us"
            lead = "  #{amount} x #{took}"

            puts "  #{lead.colorize.bold}\t#{ip}| #{instruction}"
          end

          puts "}"
        end
      end

      %machine.return!
    end

    # Interprets this input. *passes* is the amount of
    # optimization passes to perform.
    def run(passes = 8)
      if @tree || @tree_only
        puts Detree.detree(@quotes)

        return if @tree_only
      end

      offset = @@chunks.size
      compile(offset, passes)
      evaluate(offset)
    end

    def to_s(io)
      io << @file << " (" << (@distinct.join(".") || "script") << ")"
    end
  end
end
