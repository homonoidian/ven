module Ven::Library
  class Core < Component::Extension
    # XXX: Temporary. Remove!
    fun! "offset", str : Str, offset : Num do |m|
      begin
        Str.new(str.value[offset.value.to_i32...])
      rescue OverflowError | IndexError
        m.die("invalid offset #{offset} for this value: #{str}")
      end
    end

    fun! "die", cause : Str do |m|
      m.die("died: #{cause.value}")
    end

    def load
      defun "die"
      defun "offset"

      defvar "any", MType::ANY

      deftype "num", Num
      deftype "str", Str
      deftype "vec", Vec
      deftype "bool", MBool
      deftype "regex", MRegex
      deftype "type", MType

      deftype "function", MFunction
      deftype "generic", MGenericFunction
      deftype "concrete", MConcreteFunction
      deftype "builtin", MBuiltinFunction

      defvar "true", MBool.new(true)
      defvar "false", MBool.new(false)
    end
  end
end
