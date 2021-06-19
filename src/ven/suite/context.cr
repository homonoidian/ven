require "json"
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
  #
  # Can be serialized (**but not yet deserialized**).
  class Reader
    # Returns a hash of word types mapped to nud macros
    # they trigger.
    getter nuds = {} of String => Ven::Parselet::PNudMacro
    # Returns the keyword lexemes of this context.
    getter keywords = [] of String
    # Returns a hash of word types mapped to regex patterns
    # used to match them.
    getter triggers = {} of String => Regex

    # Defines a new keyword.
    delegate :<<, to: @keywords

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

    def to_json(json : JSON::Builder)
      json.object do
        json.field("nuds", @nuds)
        json.field("keywords", @keywords)
        json.field("triggers", @triggers.transform_values(&.to_s))
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

    # Maximum amount of entries in the traceback. Overflowing
    # traces are cleared (forgotten).
    MAX_TRACES = 64

    # The scope hierarchy of this context. To introduce a new,
    # deeper scope, an empty `Scope` should be appended to
    # this array.
    getter scopes = [Scope.new]

    # The list of traceback entries. It is valid until this
    # context's destruction.
    getter traces = [] of Trace

    # Whether ascending lookup is enabled.
    #
    # There are two modes of lookup: ascending (aka deep),
    # and shallow.
    #
    # Shallow lookup allows to look up and define symbols in
    # the local scope.
    #
    # Ascending lookup allows to look up and define symbols
    # not only in the local scope,  but also in the higher,
    # nonlocal scopes.
    #
    # Shallow lookups are always faster than ascending lookups.
    property ascend = true

    # Returns the amount of scopes (aka scope depth, aka nesting).
    delegate :size, to: @scopes

    # Deletes all scopes except the global.
    def clear
      @scopes.delete_at(1...)
    end

    # Returns the local scope.
    private macro local
      @scopes[-1]
    end

    # Looks up the value of *symbol*. Raises if not found.
    def [](symbol : String | VSymbol)
      self[symbol]? || raise "symbol not found"
    end

    # Returns the local scope's metacontext, if any.
    def meta : MBoxInstance?
      local["$"]?.as?(MBoxInstance)
    end

    # If the local scope has a metacontext, yields its *namespace*
    # (see `MBoxInstance#namespace`). Otherwise, returns nil.
    def with_meta_ns : Model?
      if namespace = meta.try(&.namespace)
        yield namespace
      end
    end

    # Ascends the scopes, trying to look up the value of
    # *symbol* in each one of them.
    def ascend?(symbol : String) : Model?
      @scopes.reverse_each do |scope|
        if value = scope[symbol]?
          return value
        end
      end
    end

    # Looks up the value of *symbol*.
    #
    # 1. If *symbol* is found to be one of the fields of the
    # local scope's metacontext (`$`), returns the value of
    # that field.
    #
    # 2. If *symbol* is assigned a value in the local scope,
    # returns that value.
    #
    # 3. Otherwise, given ascending lookup (see `ascend`) is
    # enabled, ascends the scopes in search of *symbol*. If
    # found, returns the corresponding value. Else, returns nil.
    def []?(symbol : String)
      with_meta_ns(&.[symbol]?) || local[symbol]? || ascend?(symbol)
    end

    # Same as `[]?(symbol : String)`, but slightly optimized
    # for *symbol*s with guaranteed nest (aka nesting).
    def []?(symbol : VSymbol)
      name = symbol.name
      nest = symbol.nest
      with_meta_ns(&.[name]?) || @scopes[nest][name]? || ascend?(name)
    end

    # Assigns the *value* to *symbol*.
    #
    # 1. If *symbol* is found in the scope at *nest*, replaces
    # its old value with *value*.
    #
    # 2. If *symbol* is a field in the local scope's metacontext,
    # replaces that field's old value with *value*.
    #
    # In any other case, assigns in the scope at *nest*.
    def []=(symbol : String, value : Model, nest = -1)
      if @scopes[nest].has_key?(symbol)
        return @scopes[nest][symbol] = value
      end

      with_meta_ns do |namespace|
        if namespace.has_key?(symbol)
          return namespace[symbol] = value
        end
      end

      @scopes[nest][symbol] = value
    end

    # :ditto:
    def []=(symbol : VSymbol, value)
      self[symbol.name, nest: symbol.nest] = value
    end

    # Introduces a deeper scope **and** a trace.
    #
    # Clears (forgets) traces if they exceed `MAX_TRACES`.
    def push(file, line, name)
      @traces.clear if @traces.size > MAX_TRACES
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
