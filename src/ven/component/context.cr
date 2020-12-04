module Ven
  class Context
    getter traces

    def initialize
      @traces = [] of Trace
      @scopes = [{} of String => Model]
    end

    # Get the latest trace
    def trace
      @traces.last
    end

    # Make an entry in the localmost (rightmost) scope
    def define(name : String, value : Model)
      @scopes.last[name] = value
    end

    # Try searching for an entry's value starting from the
    # localmost, ending with the globalmost scope
    def fetch(name : String) : Model?
      @scopes.reverse_each do |scope|
        if value = scope.fetch(name, false)
          return value.as(Model)
        end
      end
    end

    # Run a block of code in a local scope: push a new scope,
    # execute the block and pop the scope. `initial` is a
    # tuple of initial entries: keys and values. `trace` is
    # the trace the block will leave as it is executed
    def local(initial : {Array(String), Array(Model)}?, trace t : {QTag, String}, &)
      @scopes << {} of String => Model

      unless (last = @traces.last?) && {last.tag, last.name} == t
        @traces << Trace.new(t.first, t.last)
      end

      trace.amount += 1

      if initial
        initial.first.zip(initial.last) do |name, value|
          define(name, value)
        end
      end

      result = yield

      @scopes.pop

      # Properly (?) get rid of the trace
      if trace.amount > 1
        trace.amount -= 1
      elsif trace.amount == 1
        @traces.pop
      end

      result
    end

    # Clear the context, namely .clear the traces and erase all
    # but global scopes. Used to clean up after an in-function
    # error when using the REPL
    def clear
      @traces.clear
      @scopes.pop(@scopes.size - 1)

      self
    end
  end
end
