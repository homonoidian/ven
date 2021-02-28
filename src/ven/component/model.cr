require "big"

module Ven::Component
  # Model casting (aka internal conversion) will raise this
  # exception on failure (e.g. if a string cannot be parsed
  # into a number).
  class ModelCastException < Exception
  end

  # Model is the most generic Crystal type for Ven values.
  # All Ven-accessible entities must inherit either `MClass`
  # or `MStruct`.
  alias Model = MClass | MStruct

  # :nodoc:
  alias Models = Array(Model)

  alias Num = MNumber
  alias Str = MString
  alias Vec = MVector

  # :nodoc:
  macro model_template?
    # The fields this model provides access to.
    @@FIELDS = {} of String => Model

    # Converts (casts) this model into a `Num`.
    def to_num : Num
      raise ModelCastException.new("could not convert to num")
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

    # Returns a field's value for this model (or nil if the
    # field of interest does not exist). This method may also
    # be used to handle dynamic fields (fields whose values may
    # change over time).
    def field(name : String) : Model?
      @@FIELDS[name]?
    end

    # Returns whether this model is of the type *other*.
    def of?(other : MType) : Bool
      return true if other.type == MAny

      other.type.is_a?(MClass.class) \
        ? self.class <= other.type.as(MClass.class)
        : self.class <= other.type.as(MStruct.class)
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
    Component.model_template?
  end

  # A Ven value that has the Crystal type *T*.
  abstract struct MValue(T) < MStruct
    property value

    def initialize(@value : T)
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

    def true?
      @value
    end
  end

  # Ven's string data type.
  struct MString < MValue(String)
    # Returns this string parsed into a `Num`. If *parse* is
    # false, returns the length of this string instead.
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

  # Ven's regex data type.
  struct MRegex < MStruct
    property value

    def initialize(@value : Regex)
      @source = @value.to_s
    end

    def initialize(@source : String)
      @value = Regex.new(!@source.starts_with?("^") ? "^" + @source : @source)
    end

    def to_str
      Str.new(@source)
    end

    def true?
      # Any regex is true as any regex (even an empty one)
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
    Component.model_template?
  end

  # Ven's number data type.
  class MNumber < MClass
    property value

    CACHE = {} of String => BigRational

    def initialize(value : String)
      @value = (CACHE[value] ||= value.to_big_d.to_big_r)
    end

    def initialize(value : Int32 | BigDecimal)
      @value = BigRational.new(value, 1)
    end

    def initialize(@value : BigRational)
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
      io <<
        (@value.denominator == 1 \
          ? @value.numerator
          : @value.numerator / @value.denominator)
    end

    def -
      @value = -@value

      self
    end
  end

  # Ven's vector data type.
  class MVector < MClass
    property value

    def initialize(@value = Models.new)
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
  end

  # Ven's type data type. It represents other Ven data types.
  class MType < MClass
    getter name : String
    getter type : MStruct.class | MClass.class

    # Pre-defined 'any' data type.
    ANY = MType.new("any", MAny)

    def initialize(@name, @type)
    end

    def to_s(io)
      io << "type " << @name
    end

    # Returns whether this type is equal to the *other* type.
    def ==(other : MType)
      @name == other.name
    end
  end

  # The type that represents anything. It has no value and
  # cannot be directly interacted with in Crystal/Ven.
  abstract class MAny < MClass
  end

  # A parameter constrained by a Ven value.
  struct ConstrainedParameter
    getter name : String
    getter constraint : Model

    def initialize(@name, @constraint)
    end

    def to_s(io)
      io << @name << ": " << @constraint
    end

    # Returns whether this parameter's constraint matches
    # the *other* model.
    def matches(other : Model)
      if @constraint.is_a?(MType)
        return other.of?(@constraint)
      end

      @constraint.eqv?(other)
    end

    # Returns whether this constraint is equal to the *other*
    # constraint.
    def ==(other : ConstrainedParameter)
      matches(other.constraint)
    end
  end

  #:nodoc:
  alias ConstrainedParameters = Array(ConstrainedParameter)

  # An umbrella `function` type and the parent of all function
  # types Ven has to offer.
  abstract class MFunction < MClass
    def callable?
      true
    end
  end

  # Ven's most essential function type. It has an identity,
  # which is provided through a set of constraints. All concrete
  # functions have identity. All concrete functions are constrained,
  # though `MType::ANY` can be used to immitate unconstraintness.
  class MConcreteFunction < MFunction
    getter tag : QTag
    getter name : String
    getter body : Quotes
    getter arity : UInt8
    getter slurpy : Bool
    getter general : Bool
    getter params : Array(String)
    getter constraints : ConstrainedParameters

    def initialize(@tag, @name, @constraints, @body, @slurpy)
      # All constraint names except `*` are parameters.
      @params = @constraints.map(&.name).reject!("*")

      @arity = @params.size.to_u8

      @general =
        @constraints.empty? ||
        @constraints.any? &.constraint.is_a?(MType::ANY)

      @@FIELDS["name"] = Str.new(@name)
      @@FIELDS["arity"] = Num.new(@arity.to_i32)
      @@FIELDS["params"] = Vec.new(@params.map { |p| Str.new(p).as(Model) })
      @@FIELDS["slurpy?"] = MBool.new(@slurpy)
      @@FIELDS["general?"] = MBool.new(@general)
      @@FIELDS["body"] = Vec.new(@body.map { |n| n.as(Model) })
    end

    # Compares this function's arity with the *other*'s arity.
    def <=>(other : MConcreteFunction)
      @arity <=> other.arity
    end

    # Returns whether this function's signature is equal to
    # *other*'s.
    def ==(other : MConcreteFunction)
      @name == other.name && @constraints == other.constraints
    end

    def to_s(io)
      io << @name << "(" << @constraints.join(", ") << ")"
    end
  end

  # An abstract callable entity that supervises a list of concrete
  # implementations (aka variants) (see `MConcreteFunction`).
  class MGenericFunction < MFunction
    getter name : String

    # The concretes supervised by this generic.
    getter variants = Array(MConcreteFunction).new

    def initialize(@name)
      @@FIELDS["name"] = Str.new(@name)
    end

    # Adds *variant* to the list of variants this generic
    # supervises. Overrides an existing variant with the
    # same signature as the *variant*, if found one. Returns
    # the *variant* back.
    def add(variant : MConcreteFunction)
      @variants.each_with_index do |existing, index|
        if existing == variant
          return @variants[index] = variant
        end
      end

      (@variants << variant).sort! { |a, b| b <=> a }

      variant
    end

    def field(name)
      case name
      when "variants"
        Vec.new(@variants)
      when "variancy"
        Num.new(@variants.size)
      else
        @@FIELDS[name]?
      end
    end

    def to_s(io)
      io << "generic " << @name << " with " << @variants.size << " variant(s)"
    end
  end

  # Ven's builtin function type: an internal bridge from Crystal
  # to Ven.
  class MBuiltinFunction < MFunction
    getter name : String
    getter block : (Machine, Models) -> Model

    def initialize(@name, @block)
    end

    def to_s(io)
      io << "builtin " << @name
    end
  end

  # Ven's box type. Basically a concrete fun with body consisting
  # of assignments only. The scope of a box is exposed through
  # `MBoxInstance`s.
  class MBox < MClass
    getter tag : QTag
    getter name : String
    getter arity : UInt8
    getter slurpy : Bool
    getter params : Array(String)
    getter namespace : Hash(String, Quote)
    getter constraints : ConstrainedParameters

    def initialize(@tag, @name, @constraints, @namespace)
      @params = @constraints.map(&.name).reject("*")
      @arity = @params.size.to_u8
      @slurpy = @arity != @constraints.size
    end

    def eqv?(other : MBox)
      @name == other.name
    end

    def callable?
      true
    end

    def to_s(io)
      io << "box " << @name << "(" << @constraints.join(", ") << ")"
    end
  end

  # An instance of a Ven box. Provides access to instance box's
  # scope through fields.
  class MBoxInstance < MClass
    getter scope : Scope
    getter parent : MBox

    def initialize(@parent, @scope)
    end

    def field(name)
      @scope[name]?
    end

    def eqv?(other : MBox)
      @parent.eqv?(other)
    end

    def to_s(io)
      io << "instance of " << @parent
    end
  end
end
