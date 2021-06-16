require "./model"

module Ven::Suite::Context
  # This exception is raised when an assignment error occurs.
  #
  # Assignment errors exist mainly to protect some values
  # from being re-defined by the user (e.g., `true`, `false`,
  # builtin functions, etc.)
  class VenAssignmentError < Exception
  end

  # Unites instances of `Context::Reader`, `Context::Compiler`
  # and `Context::Machine`.
  class Hub
    # Returns the reader context of this hub.
    getter reader = Context::Reader.new
    # Returns the compiler context of this hub.
    getter compiler = Context::Compiler.new
    # Returns the machine context of this hub.
    getter machine = Context::Machine.new

    # Extensions already present in this hub.
    @extensions = [] of Extension.class

    delegate :[], :[]?, :[]=, to: @machine

    # Loads *extension* into this hub.
    def extend(extension : Extension)
      unless extension.class.in?(@extensions)
        extension.load(@compiler, @machine)
        @extensions << extension.class
      end
    end
  end

  # The context for a `Reader`
  #
  # The reader uses context to store and look up user-defined
  # nuds, leds and words.
  class Reader
    # Returns a hash of word types mapped to nud macros
    # they trigger.
    getter nuds = {} of String => Ven::Parselet::PNudMacro
    # Returns the keyword lexemes of this context.
    getter keywords = [] of String
    # Returns a hash of word types mapped to regex patterns
    # used to match them.
    getter triggers = {} of String => Regex

    # Returns whether *lexeme* is a keyword under this context.
    def keyword?(lexeme : String)
      lexeme.in?(@keywords)
    end

    # Defines a reader macro that will be triggered by *trigger*,
    # a word type (keyword or not).
    #
    # Does not check whether *trigger* is a valid word type.
    def []=(trigger : String, nud : Ven::Parselet::PNudMacro)
      @nuds[trigger] = nud
    end

    # Defines a trigger given *type*, word type, and regex
    # pattern *pattern*.
    def []=(type : String, pattern : Regex)
      @triggers[type] = pattern
    end

    # Defines a new keyword.
    delegate :<<, to: @keywords
  end

  # The context for a `Compiler`.
  #
  # It may use context to determine whether a symbol was defined
  # and whether it is global or local, as well as to manage
  # compile-time traceback.
  class Compiler
    alias Scope = Hash(String, Symbol)

    # The scope hierarchy. The rightmost scope is the localmost,
    # the leftmost is the globalmost.
    getter scopes : Array(Scope)
    # An array of traces, which together will form the traceback.
    getter traces = [] of Trace

    # The scopes of this context.
    @scopes = [Scope.new]

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
      #
      @traces.pop
    end

    # Evaluates the block inside a child scope.
    #
    # Yields the depth of the child scope to the block.
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

    # The scopes of this context.
    getter scopes : Array(Scope)
    # The traceback of this context.
    getter traces = [] of Trace

    # Whether to forbid lookups farther than the localmost
    # scope.
    property isolate = false

    @scopes = [Scope.new]

    # Returns the amount of scopes (aka scope depth, nesting)
    # in this context.
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
    # Respects the metacontext (`$`).
    #
    # Nests *maybe* and -1 will be searched in first.
    #
    # Returns nil if *symbol* was not found.
    def []?(symbol : String, maybe = nil)
      if value = (@scopes[-1][symbol]? || maybe.try { @scopes[maybe][symbol]? })
        return value
      end

      # Prefer *maybe*/localmost over *isolate*. Although bounds
      # seem to pass through to here. The whole thing is a bit
      # shaky, to say the least.
      return if @isolate

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

    # Returns the value of *symbol*.
    #
    # Respects the metacontext (`$`).
    #
    # Returns nil if *symbol* was not found.
    def []?(symbol : VSymbol)
      self[symbol.name, maybe: symbol.nest]?
    end

    # Makes *symbol* be *value* in the localmost scope.
    #
    # If the localmost scope includes a metacontext (`$`),
    # and that metacontext has a field named *symbol*, this
    # field will be set to *value* instead.
    #
    # Will raise `VenAssignmentError` if *symbol* already
    # exists and is an `MFunction`, whilst *value* is not.
    def []=(symbol : String, value : Model, nest = -1)
      meta = @scopes[-1]["$"]?
      prev = @scopes[nest][symbol]?

      if meta.is_a?(MBoxInstance) && meta.namespace[symbol]?
        return meta.namespace[symbol] = value
        # elsif prev.is_a?(MFunction) && !value.is_a?(MFunction)
        #   raise VenAssignmentError.new("invalid assignment target: #{prev}")
      end

      return @scopes[nest][symbol] = value
    end

    # Makes *symbol* be *value* in its nest, or, if no nest
    # specified, in the localmost scope.
    def []=(symbol : VSymbol, value : Model)
      self[symbol.name, nest: symbol.nest] = value
    end

    # Introduces a child scope **and** a child trace.
    #
    # Deletes all existing traces if the amount of them
    # exceeds `MAX_TRACES`.
    def push(file, line, name)
      if @traces.size > MAX_TRACES
        @traces.clear
      end

      @scopes << Scope.new
      @traces << Trace.new(file, line, name)
    end

    # Pops the current scope **and** the current trace.
    def pop
      @scopes.pop
      @traces.pop?
    end
  end
end
