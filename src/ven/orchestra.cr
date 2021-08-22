module Ven
  # Orchestrates the behavior of multiple programs.
  #
  # Orchestra interprets & caches `expose`s (`distinct`s are
  # more on the Inquirer side of things), resolves conflicts
  # between `Program`s, automatically injects & uninjects
  # chunk pool middleware, etc.
  #
  # The only real requirement is that the `Program`s an Orchestra
  # is provided have the same context hub as that Orchestra.
  #
  # In the future, it will probably handle patches to the
  # context hub, i.e., interactive, stateful reloading (if
  # Ven would ever be able to handle that), and so on.
  #
  # ```
  # SOURCES = {
  #   "foo.ven"  => "distinct foo; x = 1",
  #   "bar.ven"  => "distinct foo; y = 2",
  #   "baz.ven"  => "distinct baz; expose foo; z = |+| [x y]",
  #   "quux.ven" => "distinct quux; expose baz; result = [x y z]",
  # }
  #
  # PULL = Ven::Orchestra::Pull.new do |distinct|
  #   # Distinct is an array: distinct foo is ["foo"],
  #   # distinct foo.bar is ["foo", "bar"], etc.
  #   if distinct == ["foo"]
  #     ["foo.ven", "bar.ven"]
  #   elsif distinct == ["baz"]
  #     ["baz.ven"]
  #   elsif distinct == ["quux"]
  #     ["quux.ven"]
  #   end
  # end
  #
  # READ = Ven::Orchestra::Read.new do |filename|
  #   SOURCES[filename]?
  # end
  #
  # hub = Ven::Suite::CxHub.new
  #
  # orchestra = Ven::Orchestra.new(hub, PULL, READ)
  #
  # alpha = Ven::Program.new("expose foo; [x y]", hub: hub)
  # beta = Ven::Program.new("expose quux; result", hub: hub)
  #
  # puts orchestra.play(alpha)    # ==> [1 2]
  # puts orchestra.play(beta)     # ==> [1 2 3]
  # puts orchestra.play(["quux"]) # ==> [1 2 3]
  # ```
  class Orchestra
    include Suite

    # Maps the argument to Ven source code. Nil return value
    # is interpreted as an error.
    alias Read = Proc(String, String?)

    # Maps distinct to an array of readables: each entry of
    # the array is consequently `Read` for the source code.
    # Nil and empty array return value is interpreted as an
    # error.
    alias Pull = Proc(Distinct, Array(String)?)

    # Maps the given program to its result.
    alias Callback = Proc(Program, Program::Result)

    # The default `Callback`. Clears *program*'s result stack,
    # and returns the result of evaluation.
    EVALUATE = Callback.new do |program|
      program.clear
      program.result
    end

    # Returns an array of cached readables. If met one of
    # those as a dependency of some `Program`, it will not
    # be exposed.
    getter cache = [] of String

    # Initializes this Orchestra with the given context *hub*,
    # *pull* callback (see `Pull`), and *read* callback (see
    # `Read`). Also note that all programs `play`ed by this
    # orchestra in the future must have *hub* set as their
    # context hub, too.
    def initialize(@hub : CxHub, @pull : Pull, @read : Read)
      @chunks = Chunks.new
    end

    # Returns the dependency list of *program*.
    #
    # An array consisting of *program*'s distinct (if any),
    # plus all of its exposes, identical entries removed, is
    # considered the dependency list of *program*.
    private def dependencies(program : Program)
      exposes = program.exposes
      distinct = program.distinct

      (distinct ? [distinct] + exposes : exposes).uniq!
    end

    # Calls the read proc of this Orchestra with the given
    # *readable*, and dies if the returned value is nil.
    #
    # See `Read`.
    private def read(readable : String) : String
      @read.call(readable) ||
        raise ExposeError.new("could not expose: could not read '#{readable}'")
    end

    # Calls the pull proc of this Orchestra with the given
    # *distinct*, and dies if the returned array is empty,
    # or nil.
    #
    # See `Pull`.
    private def pull(distinct : Distinct) : Array(String)
      readables = @pull.call(distinct)

      if readables.nil? || readables.empty?
        raise ExposeError.new("could not pull '#{distinct.join('.')}'")
      end

      readables
    end

    # Injects poolization middlewares into *program*. Returns
    # a cleanup proc to remove them once the program finishes
    # execution under this Orchestra.
    #
    # **In an Orchestra, poolization must happen immediately
    # before evaluating the given program. Any intermediate
    # evaluations obstruct poolization**, as the middlewares
    # it creates capture the chunk pool in a vicarious state.
    private def poolize(program : Program) : Proc(Nil)
      origin = @chunks.size

      a = program.before_compile do |compiler|
        # Redirect Compiler's chunk writes to the chunk pool.
        compiler.chunks = @chunks
      end

      b = program.after_compile.add do |_, compiler, yielder|
        # Slice to lighten the load for the optimizer.
        #
        # The chunks themselves are changed inplace, and we
        # won't have to unslice, or concat, or do anything
        # like that with the chunks.
        yielder.call(@chunks[origin..], compiler)
      end

      #       c = program.after_optimize.add do |chunks, optimizer, yielder|
      #         # The optimizer does return our slice, though, so
      #         # pass the next middleware our full chunk pool.
      #         yielder.call(@chunks, optimizer)
      #       end

      d = program.before_eval do |machine|
        # We have to do this here so the users don't know
        # we're actually using a chunk pool, and there is
        # no other way!
        program.@result[-1] = @chunks

        # Set the origin to the chunk pool size prior to this
        # program's evaluation.
        machine.origin = origin
      end

      ->do
        program.before_compile.list.reject! &.hash.to_u64 == a
        program.after_compile.list.reject! &.hash.to_u64 == b
        # program.after_optimize.list.reject! &.hash.to_u64 == c
        program.before_eval.list.reject! &.hash.to_u64 == d
      end
    end

    # Pulls and reads *distinct*, makes a `Program` off the
    # resulting source code (with this Orchestra's context
    # `hub` being its context hub), `poolize`s the program,
    # and passes it to *callback*. After the callback executes,
    # ensures the program is unpoolized, and the program result
    # stack is clear.
    private def expose(distinct : Distinct, callback = EVALUATE)
      # Pull the readables that belong to the given distinct.
      readables = pull(distinct)
      readables.each do |readable|
        unless readable.in?(@cache)
          @cache << readable
          # Get the source code of the readable by passing
          # it to the read proc.
          program = Program.new(read(readable), readable, @hub)
          # Recurse on the dependencies. Infinite recursion
          # is prevented by caching the readables.
          dependencies(program).each do |dependency|
            expose(dependency, callback)
          end
          unpoolize = poolize(program)
          begin
            # Call the callback, now that we're sure *program*
            # can evaluate.
            callback.call(program)
          ensure
            # If the callback pulled the result out, the GC
            # would notice that and not deallocate. In this
            # case, give the puller a clear program to work
            # with.
            program.clear
            unpoolize.call
          end
        end
      end
    end

    # Plays *program*: poolizes it, exposes its dependencies,
    # and passes it to the *master* callback. Each dependency
    # is evaluated (or not, if you choose so) using the given
    # *children* callback.
    #
    # Raises if *program*'s hub is different from that of
    # this Orchestra.
    #
    # Does unrecoverable changes to the *program*'s (and thus
    # this Orchestra's) hub.
    #
    # Since symbols are defined on the fly, the symbols defined
    # prior to an error will anyway remain in the context. The
    # caller may decide to take snapshots of the hub, but this
    # might not help in all cases, and is a heavy operation
    # performance-wise.
    def play(program : Program, master = EVALUATE, children = EVALUATE) : Program::Result
      # Check if the program's hub, and this Orchestra's,
      # reference the same object.
      unless program.hub.same?(@hub)
        raise InternalError.new("program hub not the same as this orchestra's")
      end
      dependencies(program).each do |dependency|
        expose(dependency, children)
      end
      unpoolize = poolize(program)
      begin
        master.call(program)
      ensure
        program.clear
        unpoolize.call
      end
    end

    # Plays *distinct*. Most of the things said in `play(program)`
    # are true for this method as well, only the program to
    # play is assembled a little bit differently.
    #
    # If *distinct* has too many candidates (i.e., the pull
    # function returned more than one readable), dies, because
    # it does not know what candidate of those it got to run.
    def play(distinct : Distinct, master = EVALUATE, children = EVALUATE) : Program::Result
      readables = pull(distinct)
      # Die if multiple candidates. Although adding priority
      # / 'ability to run' flags to `distinct` declarations
      # is definitely a viable idea, or maybe analyzing them
      # somehow to see if, say, a `main` concrete is present,
      # and run those that have it.
      unless readables.size == 1
        raise ExposeError.new("too many candidates for '#{distinct.join('.')}'")
      end
      readable = readables.first
      program = Program.new(read(readable), readable, hub: @hub)
      @cache << readable
      dependencies(program).each do |dependency|
        expose(dependency, children)
      end
      unpoolize = poolize(program)
      begin
        master.call(program)
      ensure
        program.clear
        unpoolize.call
      end
    end
  end
end
