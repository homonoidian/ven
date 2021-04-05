module Ven
  alias Distinct = Array(String)

  # An abstraction over a Ven file, and one of the highest
  # Ven abstractions overall.
  #
  # Implements common context. This means that any new input
  # is evaluated in the same context where all other inputs
  # were evaluated before.
  #
  # ```
  # foo = Ven::Input.new("foo", "x = 2 + 2")
  # bar = Ven::Input.new("bar", "x + 1")
  #
  # puts foo.run # ==> 4 : Num
  # puts bar.run 3 ==> 5 : Num
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

    def initialize(@file, @source)
      @@context.extend(Library::Internal.new)

      # Rather expensive to read twice, but nah!
      connect
    end

    # Parses this input and passes each consequtive quote to
    # the block.
    private def quotes
      @@reader.read(@file, @source) do |quote|
        yield quote
      end
    end

    # Retrieves the distinct name of this input; makes a list
    # of names this input requires exposed.
    private def connect
      quotes do |quote|
        if quote.is_a?(QDistinct)
          @distinct = quote.pieces
        elsif quote.is_a?(QExpose)
          @exposes << quote.pieces
        end
      end
    end

    # Reads and compiles the resulting quotes into chunks,
    # which are then returned.
    #
    # The compiler will emit chunks with cross-chunk references
    # respecting the *offset*.
    private macro chunkize(offset)
      %compiler = Compiler.new(@@context.compiler, @file, {{offset}})

      quotes do |%quote|
        %compiler.visit(%quote)
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
    private macro complete(chunks)
      %chunks = {{chunks}}
      %chunks.each(&.complete!)
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
      %machine.start
      %machine.return!
    end

    # Interprets this input. *passes* is the amount of
    # optimization passes to perform.
    def run(passes = 8)
      offset = @@chunks.size
      compile(offset, passes)
      evaluate(offset)
    end

    def to_s(io)
      io << @file << " (" << (@distinct || "script") << ")"
    end
  end
end
