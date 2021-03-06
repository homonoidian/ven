require "./model"

module Ven::Suite
  alias Scope = Hash(String, Model)

  # The context implements the scope semantics via a *scopes*
  # stack, defines the *traces* stack for tracebacking and the
  # *underscores* stack for working with contextual values
  # (i.e., `_` and `&_`).
  class Context
    property traces

    # Context's own scope type:
    alias CScope = Hash(String, CSEntry)

    # Context scope entry's own type:
    alias CSEntry = { local: Bool, value: Model, internal: Bool }

    def initialize
      @traces = [] of Trace
      @scopes = [CScope.new]
      @underscores = [] of Model
    end

    # Returns the latest trace.
    private def trace
      @traces.last
    end

    # Creates a `CSEntry`.
    private macro entry(value, local = true, internal = false)
      { local: {{local}}, value: {{value}}, internal: {{internal}} }
    end

    # Converts a *source* `Scope` into a `CScope`.
    private def from_scope(source : Scope, local = true) : CScope
      source.transform_values { |value| entry(value, local) }
    end

    # Converts a *source* `CScope` into a `Scope`.
    private def into_scope(source : CScope) : Scope
      source.transform_values(&.[:value])
    end

    # Returns the localmost scope.
    private def scope : CScope
      @scopes.last
    end

    # Returns the localmost scope as a `Scope`.
    def scope? : Scope
      into_scope(scope)
    end

    # Binds a new local symbol *name* to *value*. Returns
    # *value* back.
    def []=(name : String, value : Model)
      scope[name] = entry(value)

      value
    end

    # Defines a symbol called *name* that will hold a *value*.
    # If same-named symbol with *local* set to false already
    # exists (local prior to global), redefines this symbol
    # to henceforth hold *value*.
    def define(name : String, value : Model, local = true, internal = false)
      target = scope

      @scopes.reverse_each do |nonlocal|
        if (existing = nonlocal[name]?) && !existing[:local]
          break begin
            local = false
            target = nonlocal
            internal = existing[:internal]
          end
        end
      end

      target[name] = entry(value, local, internal)

      value
    end

    # Retrieves a symbol called *name*. It looks for it in
    # the localmost scope first, then proceeds up to the
    # parenting scopes.
    def fetch(name : String) : Model?
      @scopes.reverse_each do |scope|
        scope[name]?.try { |it| return it[:value] }
      end
    end

    # Executes *block* in a new scope. *names* and *values*
    # are names and values the new scope will be initialized
    # with.
    def in(names : Array(String), values : Models, &block)
      yield @scopes << from_scope Scope.zip(names, values)
    ensure
      @scopes.pop
    end

    # Executes *block* in a new empty scope.
    def in(&block)
      yield @scopes << CScope.new
    ensure
      @scopes.pop
    end

    # Pushes a *scope* onto the scopes stack. Makes all
    # symbols' local be *local*.
    def inject(scope : Scope, local = true)
      @scopes << from_scope(scope, local)
    end

    # Pops a scope from the scopes stack and returns it.
    def uninject : Scope
      into_scope(@scopes.pop)
    end

    # Returns whether the evaluation is currently in a function.
    def in_fun? : Bool
      # XXX: change to something more reliable.
      scope.has_key?("$RETURNS")
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
