require "./suite/*"

module Ven
  # An individual Ven program, and a first-tier (higher is
  # more abstract) high level manager.
  #
  # High level managers are abstractions over the workhorses
  # of Ven: `Reader`, `Compiler`, `Optimizer` and `Machine`.
  # They manage the workhorses in a simple, graceful and
  # powerful way.
  #
  # ```
  # puts Program.new("1 + 1").run # 2 : Num
  # ```
  class Program
    include Suite

    # Each entry of this enum represents a step in Ven program
    # evaluation pipeline.
    #
    # The goal of Ven program evaluation pipeline is to
    # transform Ven source code into a value in a series
    # of steps.
    enum Step
      Read
      Compile
      Optimize
      Evaluate
    end

    # Returns the context hub of this program.
    getter hub : Context::Hub
    # Returns the filename (or unit name) of this program.
    getter file : String
    # Returns the source code of this program.
    getter source : String
    # Returns the distincts that this program exposes.
    getter exposes = [] of Distinct
    # Returns this program's distinct.
    getter distinct : Distinct?

    # Returns the quotes of this program.
    getter quotes = Quotes.new
    # Returns the chunks of this program.
    getter chunks = Chunks.new

    @result : Model?

    # The chunk that will be evaluated first.
    @origin = 0

    # Makes a Program.
    #
    # *source* is the source code of this program; *file* is
    # its filename (or unit name); *hub* is the context hub
    # that this program will use.
    def initialize(@source : String, @file = "untitled", @hub = Context::Hub.new,
                   @enquiry = Enquiry.new)
      @reader = Reader.new(@source, @file, @hub.reader)
      # WARNING: order is important!
      @distinct = @reader.distinct?
      @exposes = @reader.exposes
    end

    # Performs a particular *step* in Ven program evaluation
    # pipeline.
    #
    # See `Step` for the available steps.
    def step(step : Step)
      case step
      when Step::Read
        @quotes = @reader.read
      when Step::Compile
        @chunks += Compiler.compile(@quotes, @file, @hub.compiler, @origin, @enquiry)
      when Step::Optimize
        @chunks[@origin...] = Optimizer.optimize(@chunks[@origin...], @enquiry.optimize)
      when Step::Evaluate
        @result = Machine.run(@chunks, @hub.machine, @origin, @enquiry)
      end

      self
    end

    # Alias for `step`.
    def then(*args, **options)
      step(*args, **options)
    end

    # Makes chunks of *pool* precede chunks of this program,
    # as well as be available at runtime.
    #
    # Returns self.
    def import(pool : Chunks)
      @chunks = pool
      @origin = pool.size

      self
    end

    # Appends the chunks that (exclusively) this program
    # produced to *destination*.
    #
    # Returns self.
    #
    # NOTE: Mutates *destination*.
    def export(destination : Chunks)
      destination.concat(@chunks[@origin...])

      self
    end

    # Runs this program: performs all steps of Ven evaluation
    # pipeline.
    #
    # *parenthood* gets `import`ed first, and then gets
    # `export`ed. See these methods to find out about
    # the details.
    #
    # Returns self.
    def run(with parenthood = [] of Chunk)
      import(parenthood)

      step(Step::Read)
        .then(Step::Compile)
        .then(Step::Optimize)
        .then(Step::Evaluate)

      export(parenthood)
    end

    # Appends the result of this program's evaluation of the
    # string representation for an unevaluated program to *io*.
    def to_s(io)
      if @result.nil?
        io << "#{@file} of (#{@distinct.try &.join(".") || "self"})"
      else
        io << @result
      end
    end
  end
end
