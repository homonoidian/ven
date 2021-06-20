module Ven::Library
  include Suite

  class Internal < Extension
    def load(c_context, m_context)
      # Globals for types & built-in values.
      defglobal("true", MBool.new true)
      defglobal("false", MBool.new false)
      defglobal("any", MAny.new)
      defglobal("num", MType.new "num", Num)
      defglobal("str", MType.new "str", Str)
      defglobal("vec", MType.new "vec", Vec)
      defglobal("bool", MType.new "bool", MBool)
      defglobal("regex", MType.new "regex", MRegex)
      defglobal("range", MType.new "range", MRange)
      defglobal("partial", MType.new "partial", MPartial)
      defglobal("lambda", MType.new "lambda", MLambda)
      defglobal("builtin", MType.new "builtin", MBuiltinFunction)
      defglobal("generic", MType.new "generic", MGenericFunction)
      defglobal("concrete", MType.new "concrete", MConcreteFunction)
      defglobal("function", MType.new "function", MFunction)

      # Dies with *message*.
      defbuiltin "die", message : Str do
        machine.die(message.value)
      end

      # Invokes the set-referent policy for *referent*.
      defbuiltin "set-referent", reference : Model, referent : Model, value : Model do
        unless reference[referent] = value
          machine.die("#{reference} has no set-referent policy for #{referent}")
        end
        value
      end
    end
  end
end
