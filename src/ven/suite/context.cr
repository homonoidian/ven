module Ven::Suite::Context
  # The context for a `Compiler`.
  #
  # A compiler may use context to determine whether a symbol
  # was defined and whether it is global or local (which means
  # expensive and cheaper lookup correspondingly), as well as
  # to manage compile-time traceback.
  class Compiler
    alias Scope = Hash(String, Symbol)

    getter scopes : Array(Scope)
    getter traces = [] of Trace

    @toplevel = [] of String

    def initialize
      @scopes = [Scope.new]
    end

    # Declares a bound *symbol* in the localmost scope.
    def bound(symbol : String)
      @scopes.last[symbol] = :bound
    end

    # If *symbol* is declared and is bound, returns its nest.
    # Otherwise, returns nil.
    def bound?(symbol : String)
      @scopes.each_with_index do |scope, index|
        if scope[symbol]? == :bound
          return index
        end
      end
    end

    # Declares *symbol* as toplevel.
    def toplevel(symbol : String)
      @toplevel << symbol
    end

    # Returns whether *symbol* was declared as toplevel.
    def toplevel?(symbol : String)
      symbol.in?(@toplevel)
    end

    # Adds a trace for the block. This trace will point to
    # the line set by *tag*, and will be displayed under the
    # *name*.
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
    def child
      @scopes << Scope.new

      yield
    ensure
      @scopes.pop
    end
  end

  # The context for a `Machine`.
  class Machine
    alias Scope = Hash(String, Model)

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

    # Returns the value of a *symbol*.
    #
    # Raises if it was not found.
    def [](symbol : String | VSymbol)
      self[symbol]? || raise "symbol not found"
    end

    # Returns the value of a *symbol*.
    #
    # Nests *maybe* and -1 will be searched in first.
    #
    # Returns nil if it was not found.
    def []?(symbol : String, maybe = nil)
      if it = @scopes[maybe || -1][symbol]?
        return it
      end

      @scopes.reverse_each do |scope|
        if it = scope[symbol]?
          return it
        end
      end
    end

    # :ditto:
    def []?(symbol : VSymbol)
      self[symbol.name, maybe: symbol.nest]?
    end

    # Makes *symbol* be *value* in the localmost scope.
    def []=(symbol : String, value : Model)
      @scopes[-1][symbol] = value
    end

    # Makes *symbol* be *value* in its nest, or, if no nest
    # specified, in the localmost scope.
    def []=(symbol : VSymbol, value : Model)
      @scopes[symbol.nest || -1][symbol.name] = value
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
