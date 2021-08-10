require "cute"

module Ven
  # `Program` abstracts away the process of evaluating a
  # Ven program.
  #
  # Through Cute middlewares, it allows you to access, and
  # configure, the individual steps (`Program::Step`) of Ven
  # evaluation pipeline, without having to manually create
  # & setup a `Machine` object, a `Compiler` object, or any
  # other kind of object you don't really care about, let
  # alone arrange them correctly, connecting the output of
  # one to the input of another.
  #
  # Getting the result of a program:
  #
  # ```crystal
  # program = Ven::Program.new("2 + 2")
  # program.result # => 2 : Suite::Num
  # ```
  #
  # Getting the result of a particular step (for a list of
  # steps, see the subclasses of `Program::Step`):
  #
  # ```crystal
  # program = Ven::Program.new("2 + 2")
  # program.result(Ven::Program::Step::Optimize) # => Chunks
  # ```
  #
  # ### Middlewares
  #
  # `before_step` is a chain of highly unsafe, write-only
  # middleware, and `after_step` is a chain of moderately
  # safe, read-only middleware, geared mostly towards post-
  # work analysis.
  #
  # `before_step` middlewares receive an instance of the step's
  # *assignee object*, i.e., the object that does the work.
  # You can see the assignee object for any given step in
  # the `ASSIGNEE` constant, defined on that particular step.
  #
  # `after_step` middlewares receive the result of the step,
  # and an instance of the step's assignee object. You can
  # see the type of the result for any given step in the
  # `RESULT` constant, defined on that particular step.
  #
  # It is safer to prefer `before_step(&)`, `after_step(&)`
  # methods to `before_step.add`, `after_step.add`, as they
  # call the yielder automatically. This way, you cannot break
  # the middleware chain. Remember that **middleware chain
  # breakages, especially after_step, sometimes lead to
  # undefined behavior**.
  #
  # Using `before_step.add`:
  #
  # ```crystal
  # program = Ven::Program.new("2 + 2")
  #
  # program.before_read.add do |reader, yielder|
  #   puts "Before read!"
  #   # Use before_step middlewares for writing only. If you
  #   # read, you'll probably get a memory access error. Many
  #   # public, changeable values have defaults, though.
  #   reader.lineno = 1
  #   # Do not forget to call the next middleware!
  #   yielder.call(reader)
  # end
  # ```
  #
  # Using `before_step(&)`:
  #
  # ```crystal
  # program.before_read do |reader|
  #   reader.lineno = 1
  #   # No need to call the next middleware ourselves, we're
  #   # safe from breaking the chain!
  # end
  # ```
  #
  # Same can be said for `after_step.add`/`after_step(&)`.
  # Do note that if you intend to mutate the result of an
  # `after_step`, *but do not want the remaining Ven pipeline
  # to be affected*, deep copy it (although not all `Result`s
  # support deep copy, huh...).
  #
  # ```crystal
  # program = Ven::Program.new("2 + 2")
  #
  # program.after_read.add do |quotes, reader, yielder|
  #   # ...
  #   #
  #   # Do not forget to call the next middleware!
  #   yielder.call(quotes, reader)
  # end
  # ```
  #
  # ```crystal
  # program.after_read do |quotes, reader|
  #   # ...
  # end
  # ```
  class Program
    include Suite

    # A union of all possible results of executing a program.
    alias Result = Union(Quotes, Chunks, Model?)

    # Represents a step in the program evaluation pipeline.
    abstract struct Step
      # Sets the consensus `ASSIGNEE` to *klass* for this step.
      private macro defassignee(klass)
        ASSIGNEE = {{klass}}
      end

      # Sets the consensus `RESULT` to *type* for this step.
      private macro defresult(type)
        RESULT = {{type}}
      end

      macro finished
        # Contains the short names of the steps.
        NAMES = [
          {% for klass in Step.subclasses %}
            {{klass.name(generic_args: false).split("::").last.downcase}},
          {% end %}
        ]
      end

      # Reads the source into a tree of `Quote`s. Interprets
      # readtime `nud`, `led`, etc. See `Ven::Reader`.
      struct Read < Step
        defassignee Reader
        defresult Quotes
      end

      # Deeply transforms one type of quote into another:
      # pattern expressions are turned into pattern lambdas,
      # hook expressions into consensus hook calls, etc. See
      # `Ven::Transform`.
      struct Transform < Step
        defassignee Ven::Transform
        defresult Quotes
      end

      # Compiles quotes into `Chunks` of bytecode. See `Ven::Compiler`.
      struct Compile < Step
        defassignee Compiler
        defresult Chunks
      end

      # Optimizes `Chunks` of bytecode, and finalizes by
      # stitching them. See `Ven::Optimizer`.
      struct Optimize < Step
        defassignee Optimizer
        defresult Chunks
      end

      # Evaluates the optimized `Chunks`. See `Ven::Machine`.
      struct Eval < Step
        defassignee Machine
        defresult Model?
      end

      macro inherited
        # Returns whether this step is `{{@type}}`.
        def {{ @type.name(generic_args: false).split("::").last.downcase.id }}?
          true
        end

        # We need to know all subclasses of `Step`, and we
        # don't at `inherited`-time.
        macro finished
          {% verbatim do %}
            {% for klass in Step.subclasses %}
              {% unless klass == @type %}
                # Returns whether this step is `{{klass}}`.
                def {{ klass.name(generic_args: false).split("::").last.downcase.id }}?
                  false
                end
              {% end %}
            {% end %}
          {% end %}
        end
      end

      # Returns the `Step.class` that has the given *name*, or
      # nil if found no such `Step.class`.
      def self.parse?(name : String)
        {% begin %}
          case name.camelcase
            {% for subclass in Step.subclasses %}
              # We don't care about *generic_args* here, as the thing
              # is broken anyway if there are some.
              when {{subclass.name.split("::").last}}
                {{subclass}}
            {% end %}
          end
        {% end %}
      end

      # Returns the `Step.class` that has the given *name*, or
      # raises `ArgumentError` if found no such `Step.class`.
      def self.parse(name : String)
        parse?(name) || raise ArgumentError.new("no such Step.class: #{name}")
      end
    end

    # Returns the context hub of this program. See `CxHub`.
    getter hub = CxHub.new
    # Returns the source code of this program.
    getter source : String
    # Returns the filename of this program ("untitled" by default).
    getter filename : String
    # Returns the distinct of this program.
    getter distinct : Distinct?
    # Returns the distincts this program exposes.
    getter exposes = [] of Distinct

    # The program result stack, exclusively managed by &
    # accessible from the `Program`.
    @result = [] of Result

    # Initializes a `Program`.
    #
    # Immediately creates a `Reader`, and reads the `exposes`
    # and `distinct` from *source*. This mainly means that
    # currently, **you cannot change the hub after you set
    # it** to *hub*.
    def initialize(@source, @filename = "untitled", @hub = CxHub.new)
      @reader = Reader.new(@source, @filename, @hub.reader)
      @distinct = @reader.distinct?
      @exposes = @reader.exposes
    end

    # Casts the last result in the program result stack to
    # *type*. Raises if unsuccessful.
    private macro result_as(type)
      @result.last.as({{type}})
    end

    # Returns *value* cast to *type*, or, if could not cast,
    # dies of `InternalError`.
    private macro expect(value, type)
      %value = {{value}}

      unless %value.nil?
        %value.as?({{type}}) || raise InternalError.new(
          "unexpected pipeline result type: #{%value.class}; " \
          "expected: #{{{type}}}")
      end
    end

    macro finished
      {% for subclass in Step.subclasses %}
        # Get the name, and transform it so it is usable in
        # `before_<>`, `after_<>`.
        {% step = subclass.name(generic_args: false).split("::").last.downcase %}
        # Read the RESULT off the step. RESULT is the type
        # of the result of a step.
        {% result = subclass.constant(:RESULT) %}
        # Read the ASSIGNEE off the step. ASSIGNEE is the
        # object that's going to do the step.
        {% assignee = subclass.constant(:ASSIGNEE) %}

        # This middleware makes it possible to access the
        # assignee object directly, before it actually starts
        # performing the step.
        #
        # *assignee* is in the `allocate`d state, reading
        # from it is unsafe.
        Cute.middleware def before_{{step.id}}(assignee : {{assignee}}) : Nil
        end

        # Same as `before_{{step.id}}.add`, but calls the
        # yielder for you. Only the assignee object is
        # passed to the block.
        #
        # Giving up control over the chain, you gain safety.
        def before_{{step.id}}(&delegate : {{assignee}} ->)
          before_{{step.id}}.add do |%assignee, %yielder|
            delegate.call(%assignee)
            %yielder.call(%assignee)
          end
        end

        # This middleware makes it possible to modify the
        # results of a step, to reject them, or to read
        # post-work properties from the assignee object.
        Cute.middleware def after_{{step.id}}(
          result : {{result}}?,
          assignee : {{assignee}}
        ) : {{result}}?
          result
        end

        # Same as `after_{{step.id}}.add`, but calls the
        # yielder for you. Only the step result and the
        # assignee object are passed to the block.
        #
        # Giving up control over the chain, you gain safety.
        def after_{{step.id}}(&delegate : Result, {{assignee}} ->)
          after_{{step.id}}.add do |%result, %assignee, %yielder|
            delegate.call(%result, %assignee)
            %yielder.call(%result, %assignee)
          end
        end
      {% end %}
    end

    # A quick way to define a `push` method for the given *step*.
    #
    # *step* must be a subclass of `Step`, with constants
    # `ASSIGNEE` and `RESULT` defined on it.
    #
    # *args* is an Array of the arguments to `initialize`
    # an instance of `ASSIGNEE`.
    #
    # The block must receive the instance and perform the step.
    # The result of the block is the result of the step: it is
    # cast by this macro to `RESULT`, and put onto the program
    # result stack.
    private macro defpush(step, args, &block)
      macro finished
        {% step = step.resolve %}
        {% name = step.name(generic_args: false).split("::").last.downcase %}
        {% assignee = step.constant(:ASSIGNEE).resolve %}

        def push(step : {{step}}.class)
          %assignee = {{assignee}}.allocate

          # Call the before middlewares with the unsafe,
          # `allocate`d object.
          before_{{name.id}}.call(%assignee)

          %assignee.initialize({{*args}})

          # Pass the block the assignee, yield, and call the
          # after middlewares.
          {{*block.args}} = %assignee

          %value = after_{{name.id}}.call({{yield}}, %assignee)

          # Put the result onto the program result stack.
          @result << expect(%value, {{step.constant(:RESULT)}})
        end
      end
    end

    # :ditto:
    private macro defpush(step, &block)
      macro finished
        defpush {{step}}, [] of Nop do |{{*block.args}}|
          {{yield}}
        end
      end
    end

    # Reads this program, and pushes the resulting quotes
    # onto the program result stack.
    def push(step : Step::Read.class)
      if @reader.dirty
        reader = Reader.new(@source, @filename, @hub.reader)
        # Just throw them away. `Program`'s @source is immutable,
        # so are @distinct and @exposes.
        reader.distinct?
        reader.exposes
      else
        reader = @reader
      end

      before_read.call(reader)

      @result << expect(after_read.call(reader.read, reader), Quotes)
    end

    # Transforms the quotes from the top of the program result
    # stack. Pushes the resulting quotes onto the program
    # result stack.
    defpush Step::Transform do |transformer|
      transformer.transform result_as(Quotes)
    end

    # Compiles the quotes from the top of the program result
    # stack. Pushes the resulting chunks onto the program
    # result stack.
    defpush Step::Compile, [@filename, @hub.compiler] do |compiler|
      compiler.visit result_as(Quotes)
      compiler.chunks
    end

    # Optimizes the chunks from the top of the program result
    # stack. Completes the chunks (see `Suite::Chunk#complete!`),
    # and pushes them onto the program result stack.
    defpush Step::Optimize, [result_as(Chunks)] do |optimizer|
      optimizer.optimize
      optimizer.chunks.map(&.complete!)
    end

    # Evaluates the chunks from the top of the program result
    # stack. Pushes the resulting `Model` (or nil) onto the
    # program result stack.
    defpush Step::Eval, [result_as(Chunks), @hub.machine] do |machine|
      machine.start.return!
    end

    # Unhandled step: raises.
    def push(step)
      raise "unhandled step: #{step}"
    end

    # Clears the program result stack.
    def clear
      @result.clear
    end

    # Returns the result of *evaluating* this program if the
    # program result stack is empty, otherwise the last result
    # on the program result stack.
    def result
      result(Step::Eval)

      @result.last
    end

    # Pushes (see `push`) all steps leading to, and including,
    # the given *step*. Returns the last result on the program
    # result stack.
    def result(step : Step.class)
      {{Step.subclasses}}.each do |subclass|
        push(subclass)

        break if step == subclass
      end

      @result.last
    end
  end
end
