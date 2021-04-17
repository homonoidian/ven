module Ven
  alias Distinct = Array(String)

  class Input
    include Suite

    # Common reader, chunk bank and common context are class
    # variables so as to provide common execution environment
    # for every Input.

    @@chunks = Chunks.new
    @@reader = Reader.new
    @@context = Context::Hub.new

    # Whether to record the timetable.
    property measure = false
    # Whether to run inspector after this input evaluates.
    property inspect = false

    # The name of the file this Input is in.
    getter file : String
    # The source code for this Input.
    getter source : String
    # This Input's quotes.
    getter quotes = Quotes.new
    # The distincts this Input exposes.
    getter exposes = [] of Distinct
    # This Input's distinct.
    getter distinct : Distinct?
    # This Input's timetable.
    getter timetable : Machine::Timetable?

    def initialize(@file, @source, @passes = 8)
      @@context.extend(Library::Internal.new)

      @@reader.read(@file, @source) do |quote|
        if quote.is_a?(QDistinct)
          @distinct = quote.pieces
        elsif quote.is_a?(QExpose)
          @exposes << quote.pieces
        end

        @quotes << quote
      end
    end

    # Returns the class-level (aka common, super-Input)
    # context hub (see `Context::Hub`).
    def self.context
      @@context
    end

    # Compiles the quotes of this input.
    #
    # Returns the resulting chunks.
    private def compile(offset : Int32)
      Compiler.compile(@@context.compiler, @quotes, @file, offset)
    end

    # Optimizes the *chunks*.
    #
    # Returns *chunks*.
    private def optimize(chunks : Chunks)
      Optimizer.optimize(chunks, @passes)
    end

    # Appends *chunks* to the chunks bank.
    #
    # Returns *chunks*.
    private def publish(chunks : Chunks)
      @@chunks += chunks.map(&.complete!)

      chunks
    end

    # Evaluates the chunks bank, starting at *offset*.
    #
    # Returns the resulting value or nil.
    private def eval(offset : Int32)
      Machine.start(@@context.machine, @@chunks, offset) do |m|
        m.measure = @measure
        m.inspect = @inspect
        @timetable = m.timetable
      end
    end

    # Evaluates this input up until some *step*.
    #
    # Raises if *step* is not a valid step.
    #
    # ```
    # a = Input.new("a", "1 + 1")
    # a.run(:read) # -> Quotes
    # a.run(:compile) # -> Chunks
    # a.run(:optimize) # -> Chunks
    # a.run(:eval) # -> Model
    # ```
    def run(until step = :eval)
      offset = @@chunks.size

      case step
      when :read
        @quotes
      when :compile
        compile(offset)
      when :optimize
        publish optimize compile(offset)
      when :eval
        run(:optimize); eval(offset)
      else
        raise "invalid step: #{step}"
      end
    end

    def to_s(io)
      io << @file << " (" << (@distinct.try &.join(".") || "script") << ")"
    end

    # Makes an instance of `Input`, runs it up to *step* and
    # returns the result.
    #
    # ```
    # puts Input.run("foo", "2 + 2") # 4 : Num
    # ```
    def self.run(file, source, until step = :eval, passes = 8)
      new(file, source, passes).run(step)
    end
  end
end
