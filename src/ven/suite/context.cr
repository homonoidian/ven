module Ven::Suite::Context
  # A subset of context for the compiler (see `Ven::Compiler`).
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

    # Returns the nesting of a *symbol*, if it exists.
    def lookup(symbol : String)
      @scopes.reverse_each.with_index do |scope, nesting|
        if scope.has_key?(symbol)
          # *nesting* is index from the end. We need index
          # from the start.
          return (@scopes.size - 1) - nesting
        end
      end
    end

    # Declares that *symbol* exists in the local scope, and
    # that it is local.
    def let(symbol : String)
      @scopes[-1][symbol] = false
    end

    # Emulates a global lookup assignment to *symbol*.
    #
    # Returns the nesting of the scope *symbol* was assigned
    # (or defined) in.
    #
    # *global* determines whether, if globality lookup found
    # nothing, to define a global or local symbol.
    def assign(symbol : String, global = false)
      @scopes.each_with_index do |scope, nesting|
        return nesting if scope.has_key?(symbol) && scope[symbol]
      end

      @scopes[-1][symbol] = global

      @scopes.size - 1
    end

    # Traces the block during its execution.
    def trace(tag : QTag, name : String)
      @traces << Trace.new(tag, name)

      yield
    ensure
      # Compile-time errors should dup the traces, so this
      # being in `ensure` shouldn't be a problem.
      @traces.pop
    end

    # Evaluates the block inside a child scope. Passes the
    # nesting of the child scope to the block.
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

  # A subset of context for the virtual machine (see `Ven::Machine`).
  class Machine
    private alias Scope = Hash(String, Model)

    getter scopes : Array(Scope)

    def initialize
      @scopes = [Scope.new]
    end

    def [](entry : String)
      @scopes[-1][entry]
    end

    def [](entry : DSymbol)
      @scopes[entry.nesting][entry.name]
    end

    def []?(entry : String)
      @scopes[-1][entry]?
    end

    def []?(entry : DSymbol)
      @scopes[entry.depth][entry.name]?
    end

    def []=(entry : String, value : Model)
      @scopes[-1][entry] = value
    end

    def []=(entry : DSymbol, value : Model)
      @scopes[entry.nesting][entry.name] = value
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
