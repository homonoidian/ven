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
      Transform
      Compile
      Optimize
      Evaluate
    end

    # Returns the context hub of this program.
    getter hub : CxHub
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
    def initialize(@source : String, @file = "untitled", @hub = CxHub.new, @enquiry = Enquiry.new)
      @reader = Reader.new(
        @source,
        @file,
        @hub.reader,
        @enquiry
      )
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
      in Step::Read
        @quotes = @reader.read
      in Step::Transform
        @quotes = Transform.transform(@quotes)
      in Step::Compile
        @chunks += Compiler.compile(@quotes, @file, @hub.compiler, @origin, @enquiry)
      in Step::Optimize
        @chunks[@origin...] = Optimizer.optimize(@chunks[@origin...], @enquiry.optimize)
      in Step::Evaluate
        @result = Machine.run(@chunks, @hub.machine, @origin, @enquiry)
      end

      self
    end

    # Returns the result for the given *step*, or nil if
    # there wasn't any.
    def result_for(step : Step)
      case step
      in .read?, .transform?
        @quotes
      in .compile?, .optimize?
        @chunks
      in .evaluate?
        @result
      end
    end

    # Runs this program: performs all steps of Ven evaluation
    # pipeline. *pool* is an array of chunks prerequisite for
    # this `Program`.
    #
    # Returns self.
    def run(in pool = [] of Chunk)
      @chunks = pool
      @origin = pool.size

      @duration = Time.measure do
        {% for step in Step.constants %}
          step(Step::{{step}})
        {% end %}
      end

      self
    ensure
      pool.concat(@chunks[@origin..])
    end

    # Appends the result of this program's evaluation of the
    # string representation for an unevaluated program to *io*.
    def to_s(io)
      if result = @result.as?(Model)
        io << Utils.highlight(result) << " "
      end

      if duration = @duration.as?(Time::Span)
        Colorize.with.dark_gray.surround(io) do
          io << "(took " << Utils.with_unit(duration).join << ")"
        end
      end
    end
  end
end
