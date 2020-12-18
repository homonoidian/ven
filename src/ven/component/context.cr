module Ven::Component
  # Context is the bridge between different `Visitor.visit`s.
  # It implements the *scopes* stack (globalmost to localmost),
  # the *traces* stack (for tracebacking), and the *underscores*
  # stack, whose purpose is to implement  `_`, the contextual value.
  class Context
    getter traces

    def initialize
      @traces = [] of Trace
      @scopes = [{} of String => Model]
      @underscores = [] of Model
    end

    # Returns the latest trace.
    def trace
      @traces.last
    end

    # Returns the latest scope.
    def scope
      @scopes.last
    end

    # Makes an entry in the localmost (rightmost) scope.
    def define(name : String, value : Model)
      @scopes.last[name] = value
    end

    # Tries searching for an entry right-to-left, that is, from
    # the localmost to the globalmost scope.
    def fetch(name : String) : Model?
      @scopes.reverse_each do |scope|
        if value = scope.fetch(name, false)
          return value.as(Model)
        end
      end
    end

    # Makes a local scope and executes the given *block*. *initial*
    # is a tuple of keys (variable names) and values (variable values)
    # the scope will be initialized with. It may be `nil` if such
    # initialization is unwanted. *trace* is the trace left during
    # the *block*'s evaluation.
    def local(initial : {Array(String), Array(Model)}?, trace t : {QTag, String}, &)
      @scopes << {} of String => Model

      unless (last = @traces.last?) && {last.tag, last.name} == t
        @traces << Trace.new(t.first, t.last)
      end

      # += trace amount
      trace.use

      if initial
        initial.first.zip(initial.last) do |name, value|
          define(name, value)
        end
      end

      result = yield

      @scopes.pop

      # Properly (?) get rid of the trace
      if trace.amount > 1
        # -= trace amount
        trace.unuse
      elsif trace.amount == 1
        @traces.pop
      end

      result
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
    def with_u(values : Array(Model), &)
      size, _ = @underscores.size, values.each { |value| u!(value) }
      result = yield
      if @underscores.size > size
        (@underscores.size - size).times do
          @underscores.pop
        end
      end
      result
    end

    # Cleans-up the context, namely the traces. Removes all
    # scopes but the globalmost (leftmost).
    def clear
      @traces.clear
      @scopes.pop(@scopes.size - 1)

      self
    end
  end
end
