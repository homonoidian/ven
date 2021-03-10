require "big"

module Ven::Suite
  # Model casting (aka internal conversion) will raise this
  # exception on failure (e.g. if a string cannot be parsed
  # into a number.)
  class ModelCastException < Exception
  end

  # Model is the most generic Crystal type for Ven values.
  # All Ven-accessible entities must inherit either `MClass`
  # or `MStruct`, which `Model` is a union of.
  alias Model = MClass | MStruct

  # :nodoc:
  alias Models = Array(Model)

  alias Num = MNumber
  alias Str = MString
  alias Vec = MVector

  # :nodoc:
  macro model_template?
    # Converts (casts) this model into a `Num`.
    def to_num : Num
      raise ModelCastException.new("could not convert to num: #{self}")
    end

    # Converts (casts) this model into a `Str`.
    def to_str : Str
      Str.new(to_s)
    end

    # Converts (casts) this model into a `Vec`.
    def to_vec : Vec
      Vec.new([self.as(Model)])
    end

    # Converts (casts) this model into an `MBool`. Inverts
    # this MBool (applies `not`) if *inverse* is true.
    def to_bool(inverse = false) : MBool
      MBool.new(inverse ? !true? : true?)
    end

    # Returns whether this model is a false `MBool`. Note
    # that it is likely **not** the inverse of `true?`.
    def false? : Bool
      false
    end

    # Returns a field's value for this model, or nil if this
    # model has no such field.
    def field(name : String) : Model?
      nil
    end

    # Returns whether this model is of the type *other*.
    def of?(other : MType) : Bool
      other.type.is_a?(MClass.class) \
        ? self.class <= other.type.as(MClass.class)
        : self.class <= other.type.as(MStruct.class)
    end

    # :ditto:
    def of?(other : MAny)
      true
    end

    # :ditto:
    def of?(other)
      false
    end

    # Returns whether this model is equal-by-value to the
    # *other* model.
    def eqv?(other : Model) : Bool
      false
    end

    # Returns whether this model is callable.
    def callable? : Bool
      false
    end

    # Returns whether this model is semantically true.
    def true? : Bool
      true
    end
  end

  # The parent of all `Model`s represented by a Crystal struct.
  abstract struct MStruct
    Suite.model_template?
  end

  # A Ven value that has the Crystal type *T*.
  abstract struct MValue(T) < MStruct
    getter value : T

    def initialize(@value)
    end

    def eqv?(other : MValue)
      @value == other.value
    end

    def to_s(io)
      io << @value
    end
  end

  # Ven's boolean data type.
  struct MBool < MValue(Bool)
    def to_num
      Num.new(@value ? 1 : 0)
    end

    def is_bool_false?
      !@value
    end

    def true?
      @value
    end
  end

  # Ven's string data type.
  struct MString < MValue(String)
    # Returns this string parsed into a `Num`. Alternatively,
    # if *parse* is false, returns the length of this string.
    # Raises a `ModelCastException` if this string could not
    # be parsed into a number.
    def to_num(parse = true)
      Num.new(parse ? @value : @value.size)
    rescue InvalidBigDecimalException
      raise ModelCastException.new("#{self} is not a base-10 number")
    end

    def to_str
      self
    end

    def callable?
      true
    end

    def true?
      @value.size != 0
    end

    def to_s(io)
      @value.dump(io)
    end

    def [](index : Int)
      Str.new(@value[index].to_s)
    end

    delegate :size, to: @value
  end

  # Ven's regex data type.
  struct MRegex < MStruct
    getter value : Regex

    def initialize(@value)
      @source = @value.to_s
    end

    def initialize(@source : String)
      @value = Regex.new(!@source.starts_with?("^") ? "^" + @source : @source)
    end

    def to_str
      Str.new(@source)
    end

    def true?
      # Any regex is true, as any regex (even an empty one)
      # matches something.
      true
    end

    def to_s(io)
      io << "`" << @source << "`"
    end
  end

  # The parent of all `Model`s represented by a Crystal class;
  # often Models that have no particular value.
  abstract class MClass
    Suite.model_template?
  end

  # Ven's number data type.
  class MNumber < MClass
    getter value : BigDecimal

    def initialize(source : String)
      @value = source.to_big_d
    end

    def initialize(source : Int | Float)
      @value = BigDecimal.new(source)
    end

    def initialize(@value : BigDecimal)
    end

    def to_num
      self
    end

    def eqv?(other : Num)
      @value == other.value
    end

    def true?
      @value != 0
    end

    def to_s(io)
      io << @value
    end

    # Mutably negates this number. Returns self.
    def neg! : self
      @value = -@value

      self
    end
  end

  # Ven's vector data type.
  class MVector < MClass
    getter value = Models.new

    def initialize(@value)
    end

    def initialize(value : Array(MClass) | Array(MStruct))
      @value = value.map &.as(Model)
    end

    # Returns the length of this vector.
    def to_num
      Num.new(@value.size)
    end

    def to_vec
      self
    end

    def eqv?(other : Vec)
      lv, rv = @value, other.value

      lv.size == rv.size && lv.zip(rv).all? { |li, ri| li.eqv?(ri) }
    end

    def callable?
      true
    end

    def true?
      @value.size != 0
    end

    def to_s(io)
      io << "[" << @value.join(", ") << "]"
    end

    delegate :[], :size, to: @value
  end

  # Ven's type data type. It represents other Ven data types.
  class MType < MClass
    getter name : String
    getter type : MStruct.class | MClass.class

    delegate :==, to: @name

    def initialize(@name, @type)
    end

    def to_s(io)
      io << "type " << @name
    end
  end

  # The value that represents anything (in other words, the
  # value that matches on anything.)
  class MAny < MClass
  end
end
