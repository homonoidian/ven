module Ven::Suite::Context
  # The context for the compiler.
  #
  # The compiler uses context to determine the nesting of a
  # symbol and/or check if a symbol exists.
  class Compiler
    private alias Scope = Hash(String, Bool)

    getter scopes : Array(Scope)
    getter traces = [] of Trace

    def initialize
      @scopes = [Scope.new]
    end

    # Returns the nest of a *symbol* if it exists, or nil if
    # it does not.
    def lookup(symbol : String)
      @scopes.reverse_each.with_index do |scope, depth|
        if scope.has_key?(symbol)
          # *depth* is from the end, but we need it from the
          # start.
          return @scopes.size - depth - 1
        end
      end
    end

    # Declares that a local *symbol* exists in the localmost
    # scope.
    def let(symbol : String)
      @scopes[-1][symbol] = false
    end

    # Emulates a lookup assignment to *symbol*. Returns the
    # resulting nest.
    #
    # A lookup assignment is when we literally look up: we
    # check if there is a symbol in the parent scopes that
    # has the same name as this one, and whose *global* is
    # true. If found such one, "assign" to it. If didn't,
    # make a new entry in the localmost scope.
    def assign(symbol : String, global = false)
      @scopes.each_with_index do |scope, nesting|
        if scope.has_key?(symbol) && scope[symbol]
          return nesting
        end
      end

      @scopes[-1][symbol] = global

      @scopes.size - 1
    end

    # Adds a trace for the block.
    def trace(tag : QTag, name : String)
      @traces << Trace.new(tag, name)

      yield
    ensure
      # Compile-time errors should dup the traces, so this
      # being in `ensure` shouldn't be a problem.
      @traces.pop
    end

    # Evaluates the block inside a child scope. Passes the
    # depth of the child scope to the block.
    def child(& : Int32 ->)
      @scopes << Scope.new

      yield @scopes.size - 1
    ensure
      @scopes.pop
    end

    # Loads an *extension* into this context.
    def use(extension : Extension)
      extension.load(self)
    end
  end

  # The context for the Machine.
  class Machine
    private alias Scope = Hash(String, Model)

    getter scopes : Array(Scope)

    def initialize
      @scopes = [Scope.new]
    end

    def [](entry : String)
      @scopes[-1][entry]
    end

    def [](entry : VSymbol)
      @scopes[entry.nest][entry.name]
    end

    def []?(entry : String)
      @scopes[-1][entry]?
    end

    def []?(entry : VSymbol)
      @scopes[entry.nest][entry.name]?
    end

    def []=(entry : String, value : Model)
      @scopes[-1][entry] = value
    end

    def []=(entry : VSymbol, value : Model)
      @scopes[entry.nest][entry.name] = value
    end

    # Loads an *extension* into this context.
    def use(extension : Extension)
      extension.load(self)
    end

    # Pushes a new, child scope.
    def push
      @scopes << Scope.new
    end

    # Pops the current scope.
    def pop
      @scopes.pop
    end
  end
end
