module Ven::Library
  class Core < Suite::Extension
    fun! "slice", str : Str, starts : Num, ends : Num do |m|
      left, right = starts.value.numerator, ends.value.numerator

      begin
        Str.new(str.value[left..right])
      rescue OverflowError | IndexError
        m.die("invalid slice(#{starts}, #{ends}) for this value: #{str}")
      end
    end

    fun! "die", cause : Str do |m|
      m.die("died: #{cause.value}")
    end

    def load
      defun "die"
      defun "slice"

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
