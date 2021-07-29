require "json"
require "./model"

module Ven::Suite
  # Unites instances of `CxReader`, `CxCompiler`, and `CxMachine`.
  class CxHub
    # Returns the instance of reader context.
    getter reader = CxReader.new
    # Returns the instance of compiler context.
    getter compiler = CxCompiler.new
    # Returns the instance of machine context.
    getter machine = CxMachine.new

    # Extensions already loaded into this hub.
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

  # Reader context holds user-defined nuds, leds, and words.
  class CxReader
    # Returns the user-bound nud macros (with key being the
    # word type, and value a nud macro).
    getter nuds = {} of String => Parselet::PNudMacro
    # Returns the user-bound keywords.
    getter keywords = [] of String
    # Returns the user-bound words mapped to regexes they're
    # matched by.
    getter triggers = {} of String => Regex

    # Defines a new keyword.
    delegate :<<, to: @keywords

    # Returns whether *lexeme* is a keyword.
    def keyword?(lexeme : String)
      lexeme.in?(@keywords)
    end

    # Returns the word type of *trigger* in this reader context,
    # or, if not found, nil.
    def trigger?(trigger : Regex)
      @triggers.key_for?(trigger)
    end

    # Defines a reader macro that will be triggered by *trigger*,
    # a word type (does not check whether it's valid).
    def []=(trigger : String, nud : Parselet::PNudMacro)
      @nuds[trigger] = nud
    end

    # Defines a trigger given *type*, a word type, and regex
    # pattern *pattern*.
    def []=(type : String, pattern : Regex)
      @triggers[type] = pattern
    end

    # Serializes this reader context into a JSON object.
    def to_json(json : JSON::Builder)
      json.object do
        json.field("nuds", @nuds)
        json.field("keywords", @keywords)
        json.field("triggers", @triggers.transform_values(&.to_s))
      end
    end
  end

  # Compiler context is used to determine whether a symbol
  # is defined, and whether it's global or local. It also
  # supervises a compile-time traceback.
  class CxCompiler
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

  # Machine context is used to assign and retrieve values of
  # symbols runtime.
  class CxMachine
    # A particular runtime scope in the scope stack.
    private struct Scope
      # Returns whether this scope allows a superlocal borrow
      # to pass through.
      getter borrow = false
      # Returns whether this scope is isolated.
      getter isolated : Bool
      # Returns the superlocal of this scope.
      getter superlocal = Superlocal(Model).new

      def initialize(
        @scope = {} of String => Model,
        @borrow = false,
        @isolated = false
      )
      end

      # Returns this scope as hash, with `String` keys and
      # `Model` values.
      def as_h
        @scope
      end

      forward_missing_to @scope
    end

    # Returns the scope stack of this context.
    getter scopes = [Scope.new]

    # Returns the amount of scopes.
    delegate :size, to: @scopes

    # Returns the local scope.
    private macro local
      @scopes[-1]
    end

    # Returns the active scope.
    def current
      local
    end

    # `Superlocal#take?` under this context's supervision.
    def stake?
      @scopes.reverse_each do |scope|
        if value = scope.superlocal.take?
          return value
        end
        break unless scope.borrow
      end
    end

    # `Superlocal#tap?` under this context's supervision.
    def stap?
      @scopes.reverse_each do |scope|
        if value = scope.superlocal.tap?
          return value
        end
        break unless scope.borrow
      end
    end

    # `Superlocal#fill`s in the local scope.
    def sfill(value : Model)
      local.superlocal.fill(value)
    end

    # Deletes all scopes except the global.
    def clear
      @scopes.delete_at(1..)
    end

    # Introduces a deeper scope. It can be initialized with
    # some *initial* entries. It can be *isolated* (and thus
    # im*borrow*able). If the scope is not *isolated*, you
    # can specify its *borrow* separately.
    def push(borrow = false, isolated = false, initial = {} of String => Model)
      @scopes << Scope.new(initial,
        borrow: !isolated || borrow,
        isolated: isolated,
      )
    end

    # Ejects the deepest scope.
    def pop
      @scopes.pop if size > 1
    end

    # Returns the value of *symbol*. Raises if not found.
    def [](symbol : String | VSymbol)
      self[symbol]? || raise "symbol not found"
    end

    # Returns the value of *symbol*, orelse nil.
    def []?(symbol : VSymbol)
      self[symbol.name, symbol.nest]?
    end

    # Assigns *symbol* to *value*.
    def []=(symbol : VSymbol, value)
      self[symbol.name, nest: symbol.nest] = value
    end

    # Returns the metacontext box instance in *scope*,
    # orelse nil.
    def meta(scope = local)
      scope["$"]?.as?(MBoxInstance)
    end

    # Returns the namespace (see `MBoxInstance#namespace`) of
    # the metacontext box instance in *scope*, orelse nil.
    def meta_ns?(scope = local)
      meta(scope).try(&.namespace)
    end

    # Yields the namespace of the metacontext box instance in
    # *scope*, orelse returns nil.
    def meta_ns?(scope = local)
      yield meta_ns?(scope) || return
    end

    # Traverses the scopes and returns the value assigned
    # to *symbol*, or nil.
    #
    # *nest* is the index of scope in `@scopes` where *symbol*
    # is supposed to be found.
    def []?(symbol : String, nest = -1)
      # Metacontext has the highest priority everywhere, even
      # when isolated.
      if field = meta_ns?(&.[symbol]?)
        return field
      end

      # If the local scope is isolated, or has *symbol* in
      # it, return right away.
      if local.isolated || local.has_key?(symbol)
        return local[symbol]?
      end

      if value = @scopes[nest][symbol]?
        return value
      end

      # Otherwise, ascend, trying to find *symbol* in the
      # upper scopes. Take upper metacontexts into account.
      @scopes.reverse_each do |scope|
        if value = meta_ns?(scope, &.[symbol]?) || scope[symbol]?
          return value
        end
      end
    end

    # Assigns *symbol* to *value*.
    #
    # *nest* is the index of scope in `@scopes` where *symbol*
    # would like to be assigned in.
    def []=(symbol : String, value : Model, nest = -1)
      # If the local scope is isolated, or has *symbol* defined,
      # don't look at *nest* and assign immediately.
      if local.isolated || local.has_key?(symbol)
        return local[symbol] = value
      end

      # If the metacontext has a field called *symbol*,
      # assign to it.
      meta_ns? do |fields|
        return fields[symbol] = value if fields.has_key?(symbol)
      end

      @scopes[nest][symbol] = value
    end

    # Reduces all scopes of this context into one big scope.
    # Goes top-to-bottom: more local symbols override more
    # global symbols.
    def gather : Hash(String, Model)
      @scopes.reduce({} of String => Model) do |memo, scope|
        memo.merge(scope.as_h)
      end
    end

    def_clone
  end
end
