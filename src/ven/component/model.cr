require "big"

module Ven
  class ModelCastError < Exception
    # ModelCastError is be raised when to_num, to_str, to_vec,
    # etc. fail for some reason
  end

  alias Num = MNumber
  alias Str = MString
  alias Vec = MVector
  alias TypedParam = {String, MType}

  abstract class Model
    property value

    def initialize(
      @value)
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

    def ==(right : MType)
      name == right.name && type == right.type
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

  class MConcreteFunction < AbstractModel
    getter tag, name, params, constraints, body

    @params : Array(String)

    def initialize(
        @tag : QTag,
        @name : String,
        @constraints : Array(TypedParam),
        @body : Quotes)

      @params = @constraints.map(&.first)
    end

    def general?
      @params.empty? || @constraints.any? { |given| given[1].type == Model }
    end

    def to_s(io)
      io << "concrete fun " << @name << "(" << @constraints.map(&.join(": ")).join(", ") << ")"
    end
  end

  class MGenericFunction < AbstractModel
    getter name, concretes

    def initialize(@name : String)
      @concretes = [] of MConcreteFunction
    end

    # Insert a concrete implementation of this generic function.
    # Overwrite identical if it already exists.
    def add(concrete : MConcreteFunction)
      @concretes.each_with_index do |existing, index|
        if existing.constraints == concrete.constraints
          return @concretes[index] = concrete
        end
      end

      concrete.general? ? (@concretes << concrete) : @concretes.unshift(concrete)
    end

    def to_s(io)
      io << "generic fun " << @name << " with " << @concretes.size << " concrete(s)"
    end
  end

  class MBuiltinFunction < AbstractModel
    getter name, block

    def initialize(
      @name : String,
      @block : Proc(Machine, Array(Model), Model))
    end

    def to_s(io)
      io << "builtin " << @name
    end
  end
end
