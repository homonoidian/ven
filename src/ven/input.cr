module Ven
  struct Input
    include Suite

    @@chunks = Chunks.new
    @@reader = Reader.new
    @@context = Context::Hub.new

    getter file : String
    getter source : String

    def initialize(@file, @source)
      @@context.extend(Library::Internal.new)
    end

    # Interprets this input.
    #
    # *passes* is the amount of optimization passes to perform.
    def run(passes = 8)
      offset = @@chunks.size

      # This compiler will emit chunks whose cross-chunk
      # references account with the *offset*.
      compiler = Compiler.new(@@context.compiler, @file, offset)

      @@reader.read(@file, @source) do |quote|
        compiler.visit(quote)
      end

      result = compiler.result

      # After it emitted the chunks, we will optimize them.
      optimizer = Optimizer.new(result)
      optimizer.optimize(passes)

      # After the chunks were optimized, we have to complete
      # them (resolve jumps, stitch snippets, etc.).
      result.each(&.complete!)

      # Now contribute.
      @@chunks += result

      machine = Machine.new(@@context.machine, @@chunks, offset)

      machine.start
      machine.return!
    end

    def to_s(io)
      io << "<input file " << @file << ">"
    end
  end
end
