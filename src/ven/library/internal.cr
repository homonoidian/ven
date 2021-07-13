module Ven::Library
  include Suite

  class Internal < Extension
    on_load do
      # Globals for types & built-in values.
      defglobal("any", MAny.new)
      defglobal("num", MType.new "num", Num)
      defglobal("str", MType.new "str", Str)
      defglobal("vec", MType.new "vec", Vec)
      defglobal("map", MType.new "map", MMap)
      defglobal("type", MType.new "type", MType)
      defglobal("compound", MType.new "compound", MCompoundType)
      defglobal("bool", MType.new "bool", MBool)
      defglobal("regex", MType.new "regex", MRegex)
      defglobal("range", MType.new "range", MRange)
      defglobal("partial", MType.new "partial", MPartial)
      defglobal("lambda", MType.new "lambda", MLambda)
      defglobal("builtin", MType.new "builtin", MBuiltinFunction)
      defglobal("frozen", MType.new "frozen", MFrozenLambda)
      defglobal("generic", MType.new "generic", MGenericFunction)
      defglobal("concrete", MType.new "concrete", MConcreteFunction)
      defglobal("function", MType.new "function", MFunction)

      # Dies with *message*.
      defbuiltin "die", message : Str do
        machine.die(message.value)
      end

      # Sets the *subordinate* of *model* to *value*.
      defbuiltin "subordinate", model : Model, subordinate : Model, value : Model do
        unless model[subordinate] = value
          machine.die("#{model} has no subordinate policy for #{subordinate}")
        end
        value
      end

      # Returns the type of *model*.
      defbuiltin "typeof", model : Model do
        MType[model.class] || machine.die("cannot determine the type of #{model}")
      end

      # Freezes the *lambda*. See `MFrozenLambda`.
      defbuiltin "freeze", lambda : MLambda do
        lambda.freeze(machine)
      end

      # A direct binding to Crystal's `spawn`.
      defbuiltin "spawn", frozen : MFrozenLambda, args : Vec do
        spawn frozen.call(args.items)
      end

      # TEMPORARY until Ven has splats.
      #
      # ```ven
      # apply(say, ["Hello World!"])() # ==> Hello World!
      # ```
      defbuiltin "apply", callee : MFunction, args : Vec do
        MPartial.new(callee, args.items)
      end
    end
  end
end
