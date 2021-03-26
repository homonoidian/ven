module Ven::Library
  include Suite

  extension Internal do
    # Prints *message* to STDOUT. Returns Ven true (through
    # `extension` semantics).
    def say(message : Str) : Nil
      puts message
    end

    # Dies of *message*. It is a no-return.
    def die(message : Str)
      machine.die(message.value)
    end

    # Defines a local variable called *name* with value
    # *value*.
    def define(name : Str, value)
      machine.context[name.value] = value
    end

    true_ = MBool.new(true)
    false_ = MBool.new(false)

    # 'any' is not a type and not a value. It is something
    # in-between.
    any = MAny.new

    # These are the types of Ven:

    num = Num
    str = Str
    vec = Vec
    bool = MBool

    partial = MPartial
    builtin = MBuiltinFunction
    generic = MGenericFunction
    concrete = MConcreteFunction
    function = MFunction
  end
end
