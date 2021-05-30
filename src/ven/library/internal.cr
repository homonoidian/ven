module Ven::Library
  include Suite

  extension Internal do
    # Prints *message* to STDOUT. Returns it back.
    def say(message)
      puts message.to_str.value

      message
    end

    # Prints *question*, followed by whitespace, to the standard
    # out. Waits for user's reply. Returns that reply as a Str.
    def ask(question : Str)
      print("#{question.value} ")

      (line = gets) ? Str.new(line) : MBool.new(false)
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

    # Returns the *input* string offset to the right by *cut*
    # characters.
    def offset(input : Str, cut : Num) : Str
      input.value[cut.value.to_big_i...]
    end

    # Sets *reference*'s *referent* item (whatever the meaning
    # of that is) to *value*.
    def set_referent(reference, referent, value)
      unless reference[referent] = value
        machine.die("#{reference} has no set-referent policy for #{referent}")
      end

      value
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
    regex = MRegex
    range = MRange

    partial = MPartial
    lambda = MLambda
    builtin = MBuiltinFunction
    generic = MGenericFunction
    concrete = MConcreteFunction
    function = MFunction
  end
end
