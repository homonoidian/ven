module Ven::Library
  class Core < Component::Extension
    def load
      deftype "any", Model
      deftype "num", Num
      deftype "str", Str
      deftype "vec", Vec
      deftype "bool", MBool
      deftype "type", MType
      deftype "hole", MHole

      deftype "function", MFunction
      deftype "generic", MGenericFunction
      deftype "concrete", MConcreteFunction
      deftype "builtin", MBuiltinFunction

      defvar "true", MBool.new(true)
      defvar "false", MBool.new(false)
    end
  end
end
