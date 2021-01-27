require "big"

module Ven::Component
  # An exception raised when there is a conversion (cast)
  # error (e.g., in parsing a string into a number.)
  class ModelCastException < Exception
  end

  # The base type of Ven's value system and, therefore, the
  # root of Ven's type system. A union of `MClass` and `MStruct`.
  alias Model = MClass | MStruct

  # :nodoc:
  alias Models = Array(Model)

  # :nodoc:
  macro model_template?
    # The fields this model gives access to.
    @@FIELDS = {} of String => Model

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

    # Returns a field's value for this model (or nil if the
    # field of interest does not exist.)
    def field(name : String) : Model?
      @@FIELDS[name]?
    end

    # Returns whether this model is callable or not.
    def callable? : Bool
      false
    end
  end

  # A kind of `Model`s that can be safely represented as a
  # Crystal struct.
  abstract struct MStruct
    Component.model_template?
  end

  # A Ven wrapper for a particular Crystal type *T*.
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

  # A Ven boolean.
  struct MBool < MValue(Bool)
    def to_num
      Num.new(@value ? 1 : 0)
    end
  end

  # A Ven string.
  struct MString < MValue(String)
    # Returns the length of this string if *parse* is false,
    # which it is by default; otherwise, if it is true, returns
    # this string parsed into an `MNumber`.
    def to_num(parse = false)
      Num.new(parse ? @value : @value.size)
    rescue InvalidBigDecimalException
      raise ModelCastException.new("#{self} is not a base-10 number")
    end

    def to_str
      self
    end

    def to_s(io)
      @value.dump(io)
    end
  end

  # A Ven regex.
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

  # A kind of `Model`s that can be safely represented as
  # a Crystal class. Often these are `Model`s that have
  # no particular value.
  abstract class MClass
    Component.model_template?
  end

  # A Ven number, implemented with caching in mind.
  class MNumber < MClass
    property value : BigRational

    CACHE = {} of String => BigRational

    def initialize(value : String)
      @value = CACHE[value]? || (CACHE[value] = value.to_big_d.to_big_r)
    end

    def initialize(value : Int32)
      @value = BigRational.new(value, 1)
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

  # A Ven vector, essentially, an Array of `Model`s.
  class MVector < MClass
    property value

    def initialize(
      @value : Models)
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

  # A Ven type, which emboxes the name of the type and the
  # `Model` this type should then represent.
  class MType < MClass
    getter name, type

    ANY = MType.new("any", MAny)

    def initialize(
      @name : String,
      @type : MClass.class | MStruct.class)
    end

    # Returns whether this type's name and model are equal to
    # the *other*'s name and model.
    def ==(other : MType)
      @name == other.name && @type == other.type
    end

    def to_s(io)
      io << "type " << @name
    end
  end

  # A type that matches anything. It has no value and cannot
  # be directly interacted with in Crystal nor in Ven.
  abstract class MAny < MClass
  end

  # A tuple that consists of parameter's name and parameter's
  # `MType`.
  alias TypedParameter = {String, MType}

  # An umbrella `function` type, and a parent for all kinds
  # of functions Ven has.
  abstract class MFunction < MClass
    def callable?
      true
    end
  end

  # A concrete implementation of a generic function. It has,
  # amongst others, a *name*, a *body*, a *tag*, and a set of
  # *constraints* which define the very identity of any concrete
  # function. All concrete functions are constrained, but the `any`
  # constraint is used by default, allowing unconstraintness
  # to be a thing.
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

      if @slurpy
        @constraints << {"*", @constraints.last?.try(&.[1]) || MType::ANY}
      end

      @general = @slurpy || @params.empty? || @constraints.any? { |c| c[1].is_a?(MAny)  }

      @@FIELDS["name"] = Str.new(@name)
      @@FIELDS["arity"] = Num.new(@arity.to_i32)
      @@FIELDS["params"] = Vec.new(@params.map { |p| Str.new(p).as(Model) })
      @@FIELDS["slurpy?"] = MBool.new(@slurpy)
      @@FIELDS["general?"] = MBool.new(@general)
      @@FIELDS["body"] = Vec.new(@body.map { |n| n.as(Model) })
    end

    # Compares this function to *other* based on arity.
    def <=>(other : MConcreteFunction)
      params.size <=> other.params.size
    end

    def to_s(io)
      io << @name << "(" << constraints.map(&.join(": ")).join(", ") << ")"
    end
  end

  # An abstract callable entity that supervises a list of
  # implementations (variants) under the same name.
  class MGenericFunction < MFunction
    getter name

    def initialize(@name : String)
      @strict = [] of MConcreteFunction
      @general = [] of MConcreteFunction

      @@FIELDS["name"] = Str.new(@name)
    end

    # Adds a *variant*. Replaces identical variants, if found
    # any.
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

    # Returns an Array of the strict and general variants of
    # this generic.
    def variants
      @strict + @general
    end

    def field(name)
      # These are dynamic fields; their values change over
      # time. Thus, `model_template`'s static @@FIELD system
      # does not work for us so well anymore.

      case name
      when "variants"
        Vec.new(variants.map { |c| c.as(Model) })
      when "variety"
        Num.new(@general.size + @strict.size)
      else
        @@FIELDS[name]?
      end
    end

    def to_s(io)
      io << "generic " << @name << " with " << variants.size << " variant(s)"
    end
  end

  # A bridge from Crystal to Ven.
  class MBuiltinFunction < MFunction
    getter name, block

    def initialize(
      @name : String,
      @block : Proc(Machine, Models, Model))
    end

    def to_s(io)
      io << "builtin " << @name
    end
  end
end
