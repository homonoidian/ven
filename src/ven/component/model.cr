require "big"

module Ven
  class ModelCastError < Exception
  end

  abstract class Model
    property value

    def initialize(@value)
    end

    def to_num : MNumber
      raise ModelCastError.new
    end

    def to_str : MString
      MString.new(to_s)
    end

    def to_vec : MVector
      MVector.new([self])
    end
  end

  abstract class AbstractModel < Model
    @value : Nil

    def initialize
      @value = nil
    end
  end

  class MHole < AbstractModel
    def to_s(io)
      io << "hole"
    end
  end

  class MBool < Model
    @value : Bool

    def to_s(io)
      io << @value
    end

    def to_num
      MNumber.new(@value ? 1 : 0)
    end
  end

  class MNumber < Model
    @value : BigFloat | Int32

    def to_s(io)
      io << (@value % 1 == 0 ? @value.to_big_i : @value)
    end

    def to_num
      self
    end
  end

  class MString < Model
    @value : String

    def to_s(io)
      io << '"' << @value << '"'
    end

    def to_num
      MNumber.new(@value.to_big_f)
    rescue ArgumentError
      # This is getting crazy...
      MNumber.new(@value.size)
    end

    def to_str
      self
    end
  end

  class MVector < Model
    @value : Array(Model)

    def to_s(io)
      io << "[" << @value.join(", ") << "]"
    end

    def to_num
      MNumber.new(@value.size)
    end

    def to_vec
      self
    end
  end

  class MFunction < AbstractModel
    getter tag, name, params, body

    property scope

    def initialize(
      @tag : QTag,
      @name : String,
      @params : Array(String),
      @body : Quotes)
    end

    def to_s(io)
      io << "fun " << @name << "(" << @params.join(", ") << ")"
    end
  end
end
