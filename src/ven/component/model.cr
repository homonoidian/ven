require "big"

module Ven
  class ModelCastError < Exception
    # ModelCastError is be raised when to_num, to_str, to_vec,
    # etc. fail for some reason
  end

  abstract class Model
    property value

    def initialize(@value)
    end

    def to_num : MNumber
      raise ModelCastError.new("could not convert to num")
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
    @value : BigRational

    def initialize(value : BigDecimal | Int32)
      @value = value.to_big_r
    end

    def to_s(io)
      io <<
        (@value.denominator == 1 \
          ? @value.numerator
          : @value.numerator / @value.denominator)
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
      MNumber.new(@value.to_big_d)
    rescue InvalidBigDecimalException
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

  class MType < AbstractModel
    getter name, type

    def initialize(
      @name : String,
      @type : Model.class)
    end

    def to_s(io)
      io << "type " << @name
    end
  end

  class MHole < AbstractModel
    def to_s(io)
      io << "hole"
    end
  end

  alias TypedParam = {String, MType}

  class MConcreteFunction < AbstractModel
    getter tag, name, params, body

    def initialize(
      @tag : QTag,
      @name : String,
      @params : Array(TypedParam),
      @body : Quotes)
    end

    def general?
      @params.empty? || @params.any? { |given| given[1].type == Model }
    end

    def to_s(io)
      io << "concrete fun " << @name << "(" << @params.map(&.join(": ")).join(", ") << ")"
    end
  end

  class MGenericFunction < AbstractModel
    getter concretes

    def initialize(@name : String)
      @concretes = [] of MConcreteFunction
    end

    # Insert a concrete implementation of this generic function.
    # On failure (i.e., identical / overlapping function found)
    # returns false, otherwise true
    def add(concrete : MConcreteFunction) : Bool
      if concrete.general?
        @concretes.select(&.general?).each do |existing|
          # If we're general and have the same arity, we're identical
          if existing.params.size == concrete.params.size
            return false
          end
        end
        @concretes << concrete
      else
        @concretes.unshift(concrete)
      end

      true
    end

    def to_s(io)
      io << "generic fun " << @name << " with " << @concretes.size << " concrete(s)"
    end
  end
end
