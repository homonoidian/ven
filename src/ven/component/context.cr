module Ven::Component
  # The context shared between different `Visitor.visit`s.
  # It implements the *scopes* stack (globalmost to localmost),
  # the *traces* stack (for tracebacking), and the *underscores*
  # stack, whose purpose is to implement  `_`, the contextual value.
  class Context
    property traces

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

    # Walks through the scopes from the localmost to the
    # globalmost, returning true if found *$QUEUE* variable.
    def has_queue?
      @scopes.reverse_each do |scope|
        unless scope["$QUEUE"]?.nil?
          return true
        end
      end
    end

    # Appends a *value* to the queue. NOTE: does not check
    # whether a queue exists!
    def queue(value : Model)
      @scopes.reverse_each do |scope|
        if queue = scope["$QUEUE"]?
          break queue.as(Vec).value << value
        end
      end

      value
    end

    # Walks from the globalmost down to the localmost scope,
    # checking if *name* exists there and redefining it if
    # it does. Otherwise makes *name* be *value* in the
    # localmost scope.
    def define(name : String, value : Model)
      @scopes.each do |this|
        if this.has_key?(name)
          return this[name] = value
        end
      end

      scope[name] = value
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
    # initialization is unwanted.
    def local(initial : {Array(String), Array(Model)}? = nil, &)
      @scopes << {} of String => Model

      if initial
        initial.first.zip(initial.last) do |name, value|
          define(name, value)
        end
      end

      result = yield

      @scopes.pop

      result
    end

    # Records the evaluation of *block* as *trace* and properly
    # gets rid of this trace after the *block* has been executed.
    def tracing(t : {QTag, String}, &)
      @traces << Trace.new(t.first, t.last)
      result = yield
      @traces.pop

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

    # Clears the context: erases the traces, removes all
    # scopes but the globalmost (leftmost), and clears
    # the underscores stack (XXX).
    def clear
      @traces.clear
      @scopes.pop(@scopes.size - 1)

      # XXX: this is disputed. Although '_' and '&_' are
      # illegal at top-level, this may break the REPL in
      # some mysterious way.
      @underscores.clear

      self
    end
  end
end
