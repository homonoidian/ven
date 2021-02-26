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

    # Converts (casts) this model into an `MBool`. Inverses
    # (applies `not`) if *inverse* is true.
    def to_bool(inverse = false) : MBool
      MBool.new(inverse ? !true? : true?)
    end

    # Returns a field's value for this model (or nil if the
    # field of interest does not exist.) This function may
    # be used to handle dynamic fields (fields that can change
    # during execution.)
    def field(name : String) : Model?
      @@FIELDS[name]?
    end

    # Returns whether this model is callable or not.
    def callable? : Bool
      false
    end

    # Returns whether this model is true (for Ven).
    def true? : Bool
      true
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

    def true?
      @value
    end
  end

  # A Ven string.
  struct MString < MValue(String)
    # Returns the length of this string if *parse* is false,
    # which it is by default; otherwise, if it is true, returns
    # this string parsed into an `MNumber`.
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

    def true?
      # Any regex is true, as any regex (even an empty one)
      # matches something.
      true
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

    def initialize(
      @value : BigRational)
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

    def true?
      @value != 0
    end

    def -
      @value *= -1

      self
    end
  end

  # A Ven vector, essentially, an Array of `Model`s.
  class MVector < MClass
    property value

    def initialize(
      @value : Models = [] of Model)
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

    def true?
      @value.size != 0
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

  # TypedParameter is, in essence, a parameter's name and
  # parameter's `MType`.
  struct TypedParameter
    getter name, type

    def initialize(
      @name : String,
      @type : MType)
    end

    def to_s(io)
      io << @name << ": " << @type
    end
  end

  # An umbrella `function` type, and the parent of all kinds
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

      # All constraint names except `*` are parameters.
      @params = @constraints.map(&.name).reject!("*")

      # Whether or not this function is general:
      @general =
        @constraints.empty? ||
        @constraints.any?(&.type.is_a?(MType::ANY))

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

    # Returns whether this function's signature is  equal
    # to *other*'s.
    def ==(other : MConcreteFunction)
      other.name == @name &&
      other.constraints == @constraints
    end

    def to_s(io)
      io << @name << "(" << @constraints.join(", ") << ")"
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
        # Each constraint is a `TypedParameter`. With &[1] we
        # can compare just the types.
        if existing.constraints.map(&.type) == variant.constraints.map(&.type)
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

  class MBox < MClass
    getter tag : QTag,
           name : String,
           arity : UInt8,
           slurpy : Bool,
           params : Array(String),
           namespace : Hash(String, Quote),
           constraints : Array(TypedParameter)

    def initialize(@tag, @name, @constraints, @namespace)
      @params = @constraints.map(&.name).reject("*")
      @arity = @params.size.to_u8

      # If slurpy, @arity is one less:
      @slurpy = @arity != @constraints.size
    end

    def callable?
      true
    end

    def to_s(io)
      io << "box " << @name << "(" << @constraints.join(", ") << ")"
    end
  end

  class MBoxInstance < MClass
    getter parent, scope

    def initialize(
      @parent : MBox,
      @scope : Scope)
    end

    def field(name)
      @scope[name]?
    end

    def to_s(io)
      io << "instance of " << @parent
    end
  end
end
