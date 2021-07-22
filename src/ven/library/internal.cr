module Ven::Library
  include Suite

  class Internal < Extension
    on_load do
      # Globals for types (although `any` isn't really a type).
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
        model.type? || machine.die("cannot determine the type of #{model}")
      end

      # Freezes *lambda*. See `MFrozenLambda`.
      defbuiltin "freeze", lambda : MLambda do
        lambda.freeze(machine)
      end

      # Spawns a call to *frozen* lambda.
      defbuiltin "spawn", frozen : MFrozenLambda, args : Vec do
        spawn frozen.call(args.items)
      end

      # Temporary: Returns a partial given *callee*, *args*.
      # A partial will be returned even if *callee*'s arity
      # is equal to *args*'s length.
      defbuiltin "apply", callee : MFunction, args : Vec do
        MPartial.new(callee, args.items)
      end
    end
  end
end
