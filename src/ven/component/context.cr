module Ven
  class HubHasGeneralFormError < Exception
  end

  class Context
    getter traces

    def initialize
      @traces = [] of Trace
      @scopes = [{} of String => Model]
      @underscores = [] of Model
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

    # Push `values` onto the underscores (context) stack
    def u!(value : Model)
      @underscores << value
    end

    # Pop from the underscores (context) stack
    def u?
      @underscores.pop
    end

    # Return the underscores stack
    def us
      @underscores
    end

    # Push given values onto the underscore stack, evaluate
    # the block and pop the values if they weren't used
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

    # Clarify a function: declare a new MFunctionHub if
    # there was no such Hub declared (otherwise use the
    # declared one) and prepend to this hub the form given
    # todo
    def clarify(name : String, form : MFunction, meaning : Quotes)
      # TODO: wrong. have general function required
      already = fetch(name)

      if already.is_a?(MFunctionHub)
        if already.general? && meaning.empty?
          raise HubHasGeneralFormError.new
        end
        already.add(form, meaning)
      elsif already.is_a?(MFunction) && !meaning.empty?
        # If `name` is already a general function,
        # and we're the meaning function, it should
        # always be evaluated *last*.
        define(name, MFunctionHub.new(name, already).add(form, meaning))
      else
        define(name, meaning.empty? \
          ? MFunctionHub.new(name, form)
          : MFunctionHub.new(name).add(form, meaning))
      end
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
