module Ven::Component
  alias Scope = Hash(String, Model)

  # The context implements the scope semantics via a *scopes*
  # stack, defines the *traces* stack for tracebacking and the
  # *underscores* stack for working with contextual values
  # (i.e., `_` and `&_`).
  class Context
    property traces

    # Context's own scope type:
    private alias CScope = Hash(String, CSEntry)

    # Context scope entry's own type:
    private alias CSEntry = { local: Bool, value: Model }

    def initialize
      @traces = [] of Trace
      @scopes = [CScope.new]
      @underscores = [] of Model
    end

    # Returns the latest trace.
    private def trace
      @traces.last
    end

    # Returns the localmost scope.
    private def scope
      @scopes.last
    end

    # Converts a `Scope` into a `CScope`.
    private def from_scope(it : Scope) : CScope
      it.map { |k, v| { k, { local: true, value: v } } }.to_h
    end

    # Returns the localmost scope.
    def scope? : Scope
      scope.map { |k, v| {k, v[:value]} }.to_h
    end

    # Binds a new local variable *name* to *value*.
    def []=(name : String, value : Model)
      scope[name] = { local: true, value: value }

      value
    end

    # Defines a variable called *name* that will hold some
    # *value*. It uses nonlocal lookup if *local* is false:
    # this way, there will be an attempt to reassign 'the most
    # global same-named variable' first.
    def define(name : String, value : Model, local = true)
      target = scope

      @scopes.each do |subscope|
        if (it = subscope[name]?) && !it[:local]
          local = false

          break target = subscope
        end
      end

      target[name] = { local: local, value: value }

      value
    end

    # Retrieves a variable called *name*. It looks for it in
    # the localmost scope first, then proceeds up to the
    # parenting scopes.
    def fetch(name : String) : Model?
      @scopes.reverse_each do |scope|
        scope[name]?.try { |it| return it[:value] }
      end
    end

    # Executes *block* in a new scope. This new scope is also
    # passed as an argument to the block. *names* and *values*
    # are names and values the new scope will be initialized with.
    def in(names : Array(String), values : Models, &block)
      yield @scopes << from_scope Scope.zip(names, values)
    ensure
      @scopes.pop
    end

    # Executes *block* in a new scope. This new scope is also
    # passed as an argument to the block.
    def in(&block)
      yield @scopes << CScope.new
    ensure
      @scopes.pop
    end

    # Records the evaluation of *block* as *trace* and properly
    # disposes of this trace after the block has been executed.
    def tracing(trace t : {QTag, String}, &block)
      @traces << Trace.new(t.first, t.last)

      yield
    ensure
      @traces.pop
    end

    # Pushes a *value* onto the underscores stack.
    def u!(value : Model)
      @underscores << value
    end

    # Pops and returns a value from the underscores stack.
    def u?
      @underscores.pop
    end

    # Returns the underscores stack.
    def us
      @underscores
    end

    # Pushes given *values* onto the underscores stack,
    # evaluates the *block* and cleans the underscores stack
    # by removing unused *values*, if any.
    def with_u(values : Models, &)
      size, _ = @underscores.size, values.each { |value| u!(value) }

      yield
    ensure
      (@underscores.size - size.not_nil!).times do
        @underscores.pop
      end
    end
  end
end
