module Ven::Library
  include Suite

  class Internal < Extension
    def load(c : Context::Compiler)
      c.let("any")
      c.let("num")
      c.let("str")
      c.let("vec")
      c.let("bool")
      c.let("true")
      c.let("false")
      c.let("say")
    end

    def load(c : Context::Machine)
      c["any"] = MAny.new
      c["num"] = MType.new("num", Num)
      c["str"] = MType.new("str", Str)
      c["vec"] = MType.new("vec", Vec)
      c["bool"] = MType.new("bool", MBool)
      c["true"] = MBool.new(true)
      c["false"] = MBool.new(false)
      c["say"] = MBuiltinFunction.new("say", 1, -> (machine : Machine, args : Models) do
        puts args.first

        args.first
      end)
    end
  end
end
