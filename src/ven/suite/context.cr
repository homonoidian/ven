module Ven::Suite::Context
  class VenAssignmentError < Exception; end

  # Unites instances of `Context::Machine` and `Context::Compiler`.
  class Hub
    getter machine = Context::Machine.new
    getter compiler = Context::Compiler.new

    @extensions = [] of Extension.class

    delegate :[], :[]?, to: @machine

    # Loads *extension* into this hub.
    def extend(extension : Extension)
      unless extension.class.in?(@extensions)
        extension.load(@compiler, @machine)
        @extensions << extension.class
      end
    end
  end

  # The context for a `Compiler`.
  #
  # It may use context to determine whether a symbol was defined
  # and whether it is global or local, as well as to manage
  # compile-time traceback.
  class Compiler
    alias Scope = Hash(String, Symbol)

    # The scope hierarchy. The rightmost scope is the localmost,
    # and the leftmost - the globalmost.
    getter scopes : Array(Scope)

    # An array of traces, which together will form the traceback.
    getter traces = [] of Trace

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

    # Maximum amount of traceback entries. Clears the traces
    # if exceeds.
    MAX_TRACES = 64

    getter scopes : Array(Scope)
    getter traces = [] of Trace

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
    # Raises if *symbol* was not found.
    def [](symbol : String | VSymbol)
      self[symbol]? || raise "symbol not found"
    end

    # Returns the value of *symbol*.
    #
    # Respects the meta-context (`$`).
    #
    # Nests *maybe* and -1 will be searched in first.
    #
    # Returns nil *symbol* it was not found.
    def []?(symbol : String, maybe = nil)
      if value = @scopes[maybe || -1][symbol]?
        return value
      end

      @scopes.reverse_each do |scope|
        if value = scope[symbol]?
          return value
        end

        meta = scope["$"]?

        if meta.is_a?(MBoxInstance) && (value = meta.namespace[symbol]?)
          return value
        end
      end
    end

    # :ditto:
    def []?(symbol : VSymbol)
      self[symbol.name, maybe: symbol.nest]?
    end

    # Makes *symbol* be *value* in the localmost scope.
    #
    # If the localmost scope contains a meta-context (`$`),
    # and that meta-context has a field named *symbol*, this
    # field will be set to *value*.
    #
    # Will raise `VenAssignmentError` if *symbol* already exists
    # and is an `MFunction`, whilst *value* is not.
    def []=(symbol : String, value : Model, nest = -1)
      meta = @scopes[-1]["$"]?
      prev = @scopes[nest][symbol]?

      if meta.is_a?(MBoxInstance) && meta.namespace[symbol]?
        return meta.namespace[symbol] = value
      elsif prev.is_a?(MFunction) && !value.is_a?(MFunction)
        raise VenAssignmentError.new("invalid assignment target: #{prev}")
      end

      return @scopes[nest][symbol] = value
    end

    # Makes *symbol* be *value* in its nest, or, if no nest
    # specified, in the localmost scope.
    def []=(symbol : VSymbol, value : Model)
      self[symbol.name, nest: symbol.nest] = value
    end

    # Introduces a child scope and a child trace.
    #
    # Deletes all existing traces if the amount of them is
    # bigger than `MAX_TRACES`.
    def push(file, line, name)
      if @traces.size > MAX_TRACES
        @traces.clear
      end

      @scopes << Scope.new
      @traces << Trace.new(file, line, name)
    end

    # Pops the current scope and the current trace.
    def pop
      @scopes.pop
      @traces.pop?
    end
  end
end
