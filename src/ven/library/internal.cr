module Ven::Library
  include Suite

  extension Internal do
    defsym "any", MAny.new
    defsym "num", MType.new("num", Num)
    defsym "str", MType.new("str", Str)
    defsym "vec", MType.new("vec", Vec)
    defsym "bool", MType.new("bool", MBool)
    defsym "true", MBool.new(true)
    defsym "false", MBool.new(false)
  end
end
