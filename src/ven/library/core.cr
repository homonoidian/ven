require "../component/model"
require "../component/extension"

module Ven::Library
  class Core < Ven::Extension
    defun "add", x : Num, y : Num do |machine|
      machine.compute("+", x, y)
    end

    def load
      declare "add"

      deftype "any", Model
      deftype "num", Num
      deftype "str", Str
      deftype "vec", Vec
      deftype "bool", MBool
      deftype "type", MType
      deftype "hole", MHole
      deftype "generic", MGenericFunction
      deftype "concrete", MConcreteFunction

      defvar "true", MBool.new(true)
      defvar "false", MBool.new(false)
    end
  end
end
