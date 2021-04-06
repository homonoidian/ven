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

  # Different kinds of model weight. Model weight is, essentially,
  # the evaluation priority a model has. Models with higher
  # priorities must evaluate first.
  enum MWeight
    ANON_ANY = 1
    ANY
    ANON_TYPE
    TYPE
    ANON_VALUE
    VALUE
  end

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

    # Returns whether this model is of the type *other*, or
    # is equal-by-value to *other*.
    def match(other : Model)
      of?(other) || eqv?(other)
    end

    # Returns whether this model is callable.
    def callable? : Bool
      false
    end

    # Returns whether this model is semantically true.
    def true? : Bool
      true
    end

    # Returns the weight (see `MWeight`) of this model.
    def weight : MWeight
      MWeight::VALUE
    end

    # Returns the length (#) of this model.
    def length : Int32
      0
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

  # Ven's number data type.
  struct MNumber < MValue(BigDecimal)
    @@cache = {} of String => BigDecimal

    def initialize(@value : BigDecimal)
    end

    def initialize(source : String)
      @value = @@cache[source]? || (@@cache[source] = source.to_big_d)
    end

    def initialize(source : Int | Float)
      @value = BigDecimal.new(source)
    end

    def to_num
      self
    end

    def true?
      @value != 0
    end

    def length
      to_s.size
    end

    # Mutably negates this number. Returns self.
    def neg! : self
      @value = -@value

      self
    end
  end

  # Ven's boolean data type.
  struct MBool < MValue(Bool)
    def to_num
      Num.new(@value ? 1 : 0)
    end

    def false?
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

    def length
      @value.size
    end

    def to_s(io)
      @value.inspect(io)
    end

    def [](index : Int)
      Str.new(@value[index].to_s)
    end
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

    def length
      @source.size
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

  # Ven's vector data type.
  class MVector < MClass
    getter value

    def initialize(@value = Models.new)
    end

    def initialize(value : Array(MClass) | Array(MStruct))
      @value = value.map &.as(Model)
    end

    delegate :[], :<<, to: @value

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

    def length
      @value.size
    end

    def to_s(io)
      io << "[" << @value.join(", ") << "]"
    end
  end

  # Ven's type data type. It represents other Ven data types.
  class MType < MClass
    getter name : String
    getter type : MStruct.class | MClass.class

    delegate :==, to: @name

    def initialize(@name, @type)
    end

    def eqv?(other : MType)
      @name == other.name
    end

    def weight
      MWeight::TYPE
    end

    def to_s(io)
      io << "type " << @name
    end
  end

  # The value that represents anything (in other words, the
  # value that matches on anything.)
  class MAny < MClass
    def eqv?(other)
      true
    end

    def weight
      MWeight::ANY
    end

    def to_s(io)
      io << "any"
    end
  end

  # An abstract umbrella for various kinds of functions.
  abstract class MFunction < MClass
    # Returns the specificity of this function, which is 0
    # by default.
    getter specificity : Int32 do
      0
    end

    # Performs the checks that ensure this function can
    # receive *args*. Returns nil if it cannot.
    def variant?(args : Models)
      self
    end

    def callable?
      true
    end

    # Pretty-prints *params* alongside *given*.
    def pg(params : Array(String), given : Models)
      params.zip(given).map(&.join ": ").join(", ")
    end
  end

  # Ven's most essential function model.
  class MConcreteFunction < MFunction
    getter name : String
    getter arity : Int32
    getter given : Models
    getter slurpy : Bool
    getter target : Int32
    getter params : Array(String)

    def initialize(@name, @given, @arity, @slurpy, @params, @target)
    end

    # Returns how specific this concrete is.
    getter specificity do
      @params.zip(@given).map do |param, typee|
        weight = typee.weight

        # Anonymous parameters lose one weight point.
        if anonymous?(param)
          weight -= 1
        end

        weight.value
      end.sum
    end

    def variant?(args)
      count = args.size

      return unless (@slurpy && count >= @arity) || count == @arity

      args.zip?(@given) do |arg, type|
        return unless arg.match(type || @given.last)
      end

      self
    end

    def field(name)
      case name
      when "name"
        Str.new(@name)
      when "arity"
        Num.new(@arity)
      when "slurpy"
        MBool.new(@slurpy)
      when "params"
        Vec.new(params.map { |param| Str.new(param) })
      when "specificity"
        Num.new(specificity)
      end
    end

    def length
      @arity
    end

    def to_s(io)
      io << "concrete " << @name << "(" << pg(@params, @given) << ")"
    end

    # Returns whether *param* is an anonymous parameter.
    def anonymous?(param : String)
      param.in?("*")
    end

    # Returns whether this concrete's identity is equal to
    # the *other* concrete's identity. For this method to
    # return true, *other*'s specificity *and* given must
    # be equal to this'.
    def ==(other : MConcreteFunction)
      return false unless specificity == other.specificity

      @given.zip(other.given) do |our, their|
        return false unless our.eqv?(their)
      end

      true
    end
  end

  # A model that brings Crystal's `Proc`s to Ven, allowing
  # to define primitives. Supports supervisorship by an
  # `MGenericFunction`.
  class MBuiltinFunction < MFunction
    getter name : String
    getter arity : Int32
    getter callee : Proc(Machine, Models, Model)

    def initialize(@name, @arity, @callee)
    end

    # Returns how specific this builtin is. Note that in builtins
    # all arguments have the weight of `MWeight::ANY`.
    getter specificity do
      MWeight::ANY.value * @arity
    end

    def variant?(args) : self | Bool
      args.size == @arity ? self : false
    end

    def field(name)
      case name
      when "name"
        Str.new(@name)
      when "arity"
        Num.new(@arity)
      when "specificity"
        Num.new(specificity)
      end
    end

    def length
      @arity
    end

    # Returns whether this builtin's identity is equal to the
    # *other* builtin's identity.
    def ==(other : MBuiltinFunction)
      @name == other.name && @arity == other.arity
    end

    def to_s(io)
      io << "builtin " << name
    end
  end

  # An abstract callable entity that supervises a list of
  # `MFunction`s.
  class MGenericFunction < MFunction
    getter name : String

    def initialize(@name)
      @variants = [] of MFunction
    end

    delegate :[], :size, to: @variants

    # Adds *variant* to the list of variants this generic
    # supervises. Does not check if an identical variant
    # already exists, nor does it overwrite one.
    def add!(variant : MFunction) : self
      (@variants << variant).sort! do |left, right|
        right.specificity <=> left.specificity
      end

      self
    end

    # Adds *variant* to the list of variants this generic
    # supervises. Checks if an identical *variant* already
    # exists there and overwrites it with the *variant* if
    # it does,
    def add(variant : MFunction) : self
      @variants.each_with_index do |existing, index|
        if variant == existing
          @variants[index] = variant

          return self
        end
      end

      add!(variant)
    end

    def variant?(args) : MFunction?
      @variants.find &.variant?(args)
    end

    def field(name)
      case name
      when "name"
        Str.new(@name)
      when "variants"
        Vec.new(@variants)
      end
    end

    def length
      @variants.size
    end

    def to_s(io)
      io << "generic " << @name << " with " << @variants.size << " variant(s)"
    end
  end

  # A partial (withheld) call to an `MFunction`.
  #
  # Used mainly for UFCS, say, to write `1.say()` instead of
  # `say(1)`. In this example, `1.say` is a partial.
  #
  # Partials are introduced when gathering fields.
  class MPartial < MFunction
    getter args : Models
    getter function : MFunction

    def initialize(@function, @args)
    end

    delegate :field, :length, :specificity, to: @function

    def to_s(io)
      io << "partial " << @function << "(" << @args.join(", ") << ")"
    end
  end

  # Boxes are lightweight (in theory, at least) carriers of
  # scope. Through box instances (see `MBoxInstance`), they
  # provide a medium for working with custom fields.
  class MBox < MFunction
    getter name : String
    getter arity : Int32
    getter given : Models
    getter target : Int32
    getter params : Array(String)

    def initialize(@name, @given, @params, @arity, @target)
    end

    def variant?(args) : (self)?
      return unless args.size == @arity

      args.zip?(@given) do |arg, type|
        return unless arg.match(type || @given.last)
      end

      self
    end

    # Returns whether this box is equal-by-value to the
    # *other* box.
    #
    # Just compares the names of the two.
    def eqv?(other : MBox)
      @name == other.name
    end

    # Returns whether this box is the parent of the *other*
    # box instance.
    def eqv?(other : MBoxInstance)
      self == other.parent
    end

    def to_s(io)
      io << "box " << @name << "(" << pg(@params, @given) << ")"
    end
  end

  # An instance of an `MBox`.
  #
  # Carries with it its own copy of Scope (`Context::Machine::Scope`),
  # which was created at instantiation, and allows to access
  # the entries of that scope through field access.
  class MBoxInstance < MClass
    getter parent : MBox
    getter namespace : Context::Machine::Scope

    def initialize(@parent, @namespace)
    end

    # Returns one of the fields in the namespace of this box
    # instance.
    #
    # Provides two other, model specific and prioritized
    # properties: `.name` and `.parent`.
    def field(name)
      case name
      when "name"
        Str.new(@parent.name)
      when "parent"
        @parent
      else
        @namespace[name]?
      end
    end

    # Returns whether this box instance is equal to the *other*
    # box instance.
    #
    # This box instance and *other* box instance are equal if
    # and only if their hashes are equal.
    def eqv?(other : MBoxInstance)
      hash == other.hash
    end

    # Returns whether this box instance is parented by
    # the *other* box.
    def eqv?(other : MBox)
      @parent == other
    end

    def to_s(io)
      io << "instance of " << @parent
    end
  end
end
