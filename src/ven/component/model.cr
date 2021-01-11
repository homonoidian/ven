require "big"

module Ven::Component
  # An exception raised when a conversion (cast) error occurs
  # (e.g., failed converting (casting) string to number.)
  class ModelCastException < Exception
  end

  # # The base type of Ven's value system and, therefore, the
  # root of Ven's type system. Unifies `MClass` and `MStruct`.
  alias Model = MClass | MStruct

  # :nodoc:
  macro model_template?
    FIELDS = {} of String => Model

    # Converts (casts) this model into an `MNumber`.
    def to_num : MNumber
      raise ModelCastException.new("could not convert to num")
    end

    # Converts (casts) this model into an `MString`.
    def to_str : MString
      MString.new(to_s)
    end

    # Converts (casts) this model into an `MVector`.
    def to_vec : MVector
      MVector.new([self.as(Model)])
    end

    # Returns a field's value for this model.
    def field(name : String) : Model?
      FIELDS[name]?
    end

    # Returns whether this model is callable or not.
    def callable? : Bool
      false
    end
  end

  # A kind of `Model` for value objects (represented by Crystal `struct`).
  abstract struct MStruct
    Component.model_template?
  end

  abstract struct MValue(T) < MStruct
    property value

    def initialize(
      @value : T)
    end

    def to_s(io)
      io << @value
    end
  end

  # :nodoc:
  alias Num = MNumber

  # :nodoc:
  alias Str = MString

  # :nodoc:
  alias Vec = MVector

  # Ven boolean. Emboxes a `Bool`.
  struct MBool < MValue(Bool)
    def to_num
      Num.new(@value ? 1 : 0)
    end
  end

  # Ven number. Emboxes a `BigRational`.
  struct MNumber < MStruct
    property value : BigRational

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

  # Ven string. Emboxes a `String`.
  struct MString < MValue(String)
    SEQUENCES = {
      "\\n" => "\n",
      "\\t" => "\t",
      "\\r" => "\r",
      "\\\"" => "\"",
      "\\\\" => "\\"
    }

    # Evaluate the escape sequences in the *operand* String.
    def self.rawen!(operand : String)
      SEQUENCES.each do |escape, raw|
        operand = operand.gsub(escape, raw)
      end

      operand
    end

    # Parse this string into a number.
    def parse_num
      Num.new(@value.to_big_d)
    rescue InvalidBigDecimalException
      raise ModelCastException.new("#{self} is not a base-10 number")
    end

    # Return the length of this string.
    def to_num
      Num.new(@value.size)
    end

    def to_str
      self
    end

    def to_s(io)
      @value.dump(io)
    end
  end

  # Ven regex. Emboxes a `Regex`.
  struct MRegex < MStruct
    property value

    def initialize(
      @value : Regex,
      @string : String = @value.to_s)
    end

    def to_s(io)
      io << "`" << @string << "`"
    end

    def to_str
      Str.new(@string)
    end
  end

  # A kind of `Model` for reference entities and entities
  # without a value (represented by Crystal `class`).
  abstract class MClass
    Component.model_template?
  end

  # Ven vector. Emboxes an Array of Models.
  class MVector < MClass
    property value

    def initialize(
      @value : Array(Model))
    end

    # Returns the length of this vector.
    def to_num
      Num.new(@value.size)
    end

    def to_vec
      self
    end

    def callable?
      true
    end

    def to_s(io)
      io << "[" << @value.join(", ") << "]"
    end
  end

  # Ven type. Emboxes a typename and the model class this
  # type represents.
  class MType < MClass
    getter name, type

    def initialize(
      @name : String,
      @type : MClass.class | MStruct.class)
    end

    # Returns whether this type's name and type are equal to
    # the *other*'s name and type.
    def ==(other : MType)
      name == other.name && type == other.type
    end

    def to_s(io)
      io << "type " << @name
    end
  end

  # A type that matches anything. Has no value and cannot be
  # instantiated from Crystal (nor can it be from Ven).
  abstract class MAny < MClass
  end

  alias TypedParameter = {String, MType}

  # An umbrella `function` type.
  abstract class MFunction < MClass
    def callable?
      true
    end
  end

  # A variant of a generic function. Emboxes this variation's
  # *name*, *body*, *tag* and constraints. All functions are
  # constrained, but `any` restriction is used by default
  # (it matches everything).
  class MConcreteFunction < MFunction
    getter tag : QTag,
      name : String,
      body : Quotes,
      slurpy : Bool,
      params : Array(String),
      constraints : Array(TypedParameter),
      general : Bool,
      arity : UInt8

    def initialize(@tag, @name, @constraints, @body, @slurpy)
      @arity = @constraints.size.to_u8
      @params = @constraints.map(&.first)
      @general = @slurpy || @params.empty? || @constraints.any? { |c| c[1].is_a?(MAny)  }

      FIELDS["name"] = Str.new(@name)
      FIELDS["arity"] = Num.new(@arity.to_i32)
      FIELDS["params"] = Vec.new(@params.map { |p| Str.new(p).as(Model) })
      FIELDS["slurpy?"] = MBool.new(@slurpy)
      FIELDS["general?"] = MBool.new(@general)
    end

    # Compares this function to *other* based on arity.
    def <=>(other : MConcreteFunction)
      params.size <=> other.params.size
    end

    def to_s(io)
      io << @name << "(" << @constraints.map(&.join(": ")).join(", ") << ")"
    end
  end

  # An abstract callable entity that manages a list of variants
  # (see `MConcreteFunction`). The model Emboxes the name of
  # this generic and the list of variants.
  class MGenericFunction < MFunction
    getter name

    def initialize(@name : String)
      @strict = [] of MConcreteFunction
      @general = [] of MConcreteFunction

      FIELDS["name"] = Str.new(@name)
    end

    # Adds a *variant*. Replaces identical variants, if found any.
    def add(variant : MConcreteFunction)
      target = variant.general ? @general : @strict

      target.each_with_index do |existing, index|
        if existing.constraints == variant.constraints
          # Overwrite & return if found an identical variant:
          return target[index] = variant
        end
      end

      (target << variant).sort! { |a, b| b <=> a }

      variant
    end

    # Returns the strict and general variants this generic has
    # under one Array.
    def variants
      @strict + @general
    end

    def field(name)
      case name
      when "variants"
        Vec.new(variants.map { |c| c.as(Model) })
      when "variety"
        Num.new(@general.size + @strict.size)
      else
        FIELDS[name]?
      end
    end

    def to_s(io)
      io << "generic " << @name << " with " << variants.size << " variant(s)"
    end
  end

  # One of the bridges from Crystal to Ven. The model emboxes
  # the name of this builtin and a Crystal Proc. This Proc
  # takes two arguments: the first for an instance of `Machine`,
  # the other for an Array of arguments; and returns a Model.
  class MBuiltinFunction < MFunction
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
