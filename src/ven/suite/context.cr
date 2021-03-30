module Ven::Suite::Context
  # The context for a `Compiler`.
  #
  # A compiler may use context to determine where (and whether)
  # a symbol was defined, as well as to manage compile-time
  # traceback.
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
      @scopes.each_with_index do |scope, nest|
        if scope.has_key?(symbol) && scope[symbol]
          return nest
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
  end

  # The context for a `Machine`.
  class Machine
    private alias Scope = Hash(String, Model)

    # The scope hierarchy. The rightmost scope is the localmost,
    # and the leftmost - the globalmost.
    getter scopes : Array(Scope)

    def initialize
      @scopes = [Scope.new]
    end

    delegate :size, to: @scopes

    # Deletes all scopes except the globalmost.
    def clear
      @scopes.delete_at(1...)
    end

    # Returns the nest of a *symbol* if it exists in one of
    # the scopes, or nil if it does not.
    def nest?(symbol : String)
      @scopes.reverse_each.with_index do |scope, depth|
        return @scopes.size - depth - 1 if scope.has_key?(symbol)
      end
    end

    # Returns the value for a *symbol*.
    #
    # Raises if it was not found.
    def [](symbol : String)
      @scopes[-1][symbol]
    end

    # :ditto:
    def [](symbol : VSymbol)
      unless nest = symbol.nest || nest?(symbol.name)
        raise "symbol not found: #{symbol}"
      end

      @scopes[nest][symbol.name]
    end

    # Returns the value for a *symbol*.
    #
    # Returns nil if it was not found.
    def []?(symbol : String)
      @scopes[nest?(symbol) || return][symbol]?
    end

    # :ditto:
    def []?(symbol : VSymbol)
      @scopes[symbol.nest || nest?(symbol.name) || return][symbol.name]?
    end

    # Makes *symbol* be *value* in its nest.
    #
    # Assumes *symbol*'s nest is not nil.
    def []=(symbol : String, value : Model)
      @scopes[-1][symbol] = value
    end

    # :ditto:
    def []=(symbol : VSymbol, value : Model)
      @scopes[symbol.nest.not_nil!][symbol.name] = value
    end

    # Introduces a child scope.
    def push
      @scopes << Scope.new
    end

    # Pops the current scope.
    def pop
      @scopes.pop
    end
  end
end
