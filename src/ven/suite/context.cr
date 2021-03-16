require "./model"

module Ven::Suite
  class Context
    private alias Scope = Hash(String, Entry)
    private alias Entry = { global: Bool, value: Model }

    def initialize
      @scopes = [Scope.new]
    end

    # Defines an `Entry` in *target*. Returns the *value* back.
    private macro set!(target, name, global, value)
      %value = {{value}}
      {{target}}[{{name}}] = { global: {{global}}, value: %value }
      %value
    end

    # Defines a local variable, *name*, in the current scope.
    def []=(name : String, value : Model)
      set!(@scopes.last, name, false, value)
    end

    def [](name : String)
      @scopes.last[name][:value]
    end

    def [](name : String, ord : Int32)
      @scopes[ord][name][:value]
    end

    # Defines an entry *name* with value *value*. Overrides
    # any existing entry with the same *name*. If *global* is
    # true, the new entry will be global: any other `define`,
    # given the same *name*, will re-define the global variable
    # instead of assigning/redefining a local one.
    def define(name : String, value : Model, global = false)
      target = @scopes.last

      @scopes.reverse_each do |scope|
        if scope[name]?.try(&.[:global])
          global = true
          target = scope
        end
      end

      set!(target, name, global, value)
    end

    # Tries to fetch the value of *name* in the current scope,
    # or in the parent scope, or in the parent of the parent
    # scope, and so on. Returns the fetched value if did find
    # one, or `nil` if did not.
    def fetch(name : String)
      if it = @scopes.last[name]?
        return it[:value]
      end

      @scopes.reverse_each do |scope|
        if it = scope[name]?
          return it[:value]
        end
      end
    end

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
