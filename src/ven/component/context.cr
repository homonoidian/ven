module Ven::Component
  alias Scope = Hash(String, Model)

  # The context implements the scope semantics via a *scopes*
  # stack, defines the *traces* stack for tracebacking and the
  # *underscores* stack for working with contextual values
  # (i.e., `_` and `&_`).
  class Context
    property traces

    def initialize
      @traces = [] of Trace
      @scopes = [Scope.new]
      @underscores = [] of Model
    end

    # Returns the latest trace.
    def trace
      @traces.last
    end

    # Returns the innermost scope.
    def scope
      @scopes.last
    end

    # Walks through the scopes, from the localmost to the
    # globalmost, returning true if found a *$QUEUE* variable.
    def has_queue?
      @scopes.reverse_each do |scope|
        unless scope["$QUEUE"]?.nil?
          return true
        end
      end
    end

    # Appends a *value* to the queue.
    # NOTE: does not check whether a queue exists.
    def queue(value : Model)
      @scopes.reverse_each do |scope|
        if queue = scope["$QUEUE"]?
          break queue.as(Vec).value << value
        end
      end

      value
    end

    # Makes a scope entry for *name* with value *value* in the
    # outermost scope *if it existed before* and in the innermost
    # scope if it had not.
    def define(name : String, value : Model)
      @scopes.each do |this|
        if this.has_key?(name)
          return this[name] = value
        end
      end

      scope[name] = value
    end

    # Tries to search for *name* in the closest scope possible.
    def fetch(name : String) : Model?
      @scopes.reverse_each do |scope|
        if value = scope.fetch(name, false)
          return value.as(Model)
        end
      end
    end

    # Executes *block* in a new scope. This new scope is also
    # passed as an argument to the block. *names* and *values*
    # are names and values the new scope will be initialized with.
    def in(names : Array(String), values : Models, &block : Scope ->)
      yield (@scopes << Scope.zip names, values).last
    ensure
      @scopes.pop
    end

    # Executes *block* in a new scope. This new scope is also
    # passed as an argument to the block.
    def in(&block : Scope ->)
      yield (@scopes << Scope.new).last
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
