require "../component/model"
require "../component/extension"

module Ven::Library
  class Core < Component::Extension
    fun! "add", x : Num, y : Num do |machine|
      machine.compute("+", x, y)
    end

    def load
      defun "add"

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
