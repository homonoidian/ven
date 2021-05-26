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

  # Model weight is, simply speaking, the priority, or
  # definedness, of a model.
  #
  # Used in, say, generics to determine the order in which
  # the subordinate concretes should be sorted.
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

    # Converts (casts) this model into an `MBool` (inverting
    # the resulting bool if *inverse* is true).
    def to_bool(inverse = false) : MBool
      MBool.new(inverse ? !true? : true?)
    end

    # Returns whether this model is semantically true.
    def true? : Bool
      true
    end

    # Returns whether this model is a false `MBool`.
    #
    # This is likely **not** the inverse of `true?`.
    def false? : Bool
      false
    end

    # Returns whether this model is callable.
    def callable? : Bool
      false
    end

    # Returns whether this model is indexable.
    def indexable? : Bool
      false
    end

    # Returns whether this model is of type *other*.
    def of?(other : MType) : Bool
      other.type.is_a?(MClass.class) \
        ? self.class <= other.type.as(MClass.class)
        : self.class <= other.type.as(MStruct.class)
    end

    # :ditto:
    def of?(other)
      other.is_a?(MAny)
    end

    # Returns whether this model is equal-by-value to *other*.
    def eqv?(other : Model) : Bool
      false
    end

    # Returns whether this model is of type *other*, or is
    # equal-by-value to *other*.
    #
    # This is mostly useful when matching arguments against
    # the `given` appendix, hence the name.
    def match(other : Model) : Bool
      of?(other) || other.eqv?(self)
    end

    # Returns the weight (see `MWeight`) of this model.
    def weight : MWeight
      MWeight::VALUE
    end

    # Returns a field's value for this model, or nil if this
    # model has no such field.
    #
    # This method may be overridden by the subclass if it
    # wishes to support the following syntax:
    #
    # ```ven
    # foo.field1;
    # foo.field2;
    # foo.field3;
    # foo.[field1, field2, field3];
    # foo.("field1");
    # ```
    #
    # Where `foo` is this model.
    def field(name : String) : Model?
    end

    # Returns the length of this model.
    #
    # By default, stringifies this model and returns the
    # length of the resulting string.
    def length : Int32
      to_s.size
    end

    # Returns *index*-th item of this model.
    #
    # Subclasses may override this method to add indexing
    # support.
    #
    # Returns nil if found no *index*-th item.
    def []?(index : MNumber) : Model?
      self[index.to_i]?
    end

    # :ditto:
    def []?(index : Int) : Model?
    end

    # :ditto:
    def []?(index)
    end

    # Returns a subset of items in this model.
    #
    # Subclasses may override this method to add subset
    # support.
    #
    # Returns nil if *range* is invalid (too long, etc.)
    def []?(range : MRange) : Model?
      self[range.start.to_i...range.end.to_i]?
    end

    # :ditto:
    def []?(index : Range) : Model?
    end

    # Set-referent is a way of making the following syntax
    # support this model:
    #
    # ```ven
    # foo(referent) = value
    # ```
    #
    # Where `foo` is this model.
    #
    # Returns nil if found no *referent* / has no support for
    # such referent.
    def []=(referent : Model, value : Model) : Model?
    end
  end

  # The parent of all Struct `Model`s.
  abstract struct MStruct
    Suite.model_template?
  end

  # A model that holds a value of type *T*.
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

  # :nodoc:
  alias MNumberType = Int32 | Int64 | BigDecimal

  # Ven's number data type (type num).
  #
  # Uses ladder-like technique to get a numeric value from
  # string input: Int32 -> Int64 -> BigDecimal. Any float
  # is a BigDecimal.
  struct MNumber < MValue(MNumberType)
    def initialize(@value : MNumberType)
    end

    def initialize(input : String)
      @value = input.to_i? || input.to_i64? || input.to_big_d
    end

    def initialize(value : BigInt | Float)
      @value = value.to_big_d
    end

    def to_num
      self
    end

    def true?
      @value != 0
    end

    def match(range : MRange)
      range.includes?(@value)
    end

    # Returns the Int32 version of this number.
    #
    # Raises `ModelCastException` on overflow.
    def to_i : Int32
      case @value
      in Int32
        @value.as(Int32)
      in Int64, BigDecimal
        @value.to_i32
      end
    rescue OverflowError
      raise ModelCastException.new(
        "internal number conversion overflow: to_i")
    end

    # Returns the Int64 version of this number.
    #
    # Raises `ModelCastException` on overflow.
    def to_i64 : Int64
      @value.to_i64? || raise ModelCastException.new(
        "internal number conversion overflow: to_i64")
    end

    # Returns the BigDecimal version of this number.
    def to_big_d : BigDecimal
      @value.to_big_d
    end

    # Negates this number.
    def -
      Num.new(-@value)
    end
  end

  # Ven's boolean data type (type bool).
  struct MBool < MValue(Bool)
    def to_num
      Num.new(@value ? 1 : 0)
    end

    def true?
      @value
    end

    def false?
      !@value
    end
  end

  # Ven's string data type (type str).
  #
  # Ven strings are immutable.
  struct MString < MValue(String)
    delegate :size, to: @value

    # Converts this string into a `Num`.
    #
    # If *parse* is true, it parses this string into a number.
    # Raises `ModelCastException` on parse error.
    #
    # If *parse* is false, it returns the length of this string.
    def to_num(parse = true)
      Num.new(parse ? @value : size)
    rescue InvalidBigDecimalException
      raise ModelCastException.new("'#{value}' is not a base-10 number")
    end

    def to_str
      self
    end

    def true?
      size != 0
    end

    def callable?
      true
    end

    def indexable?
      true
    end

    def length
      size
    end

    def []?(index : Int)
      @value[index]?.try { |char| Str.new(char.to_s) }
    end

    def []?(range : Range)
      @value[range]?.try { |substring| Str.new(substring) }
    end

    def to_s(io)
      @value.inspect(io)
    end
  end

  # Ven's regular expression data type.
  struct MRegex < MStruct
    getter value : Regex

    def initialize(@value)
      @original = @value.to_s
    end

    def initialize(@original : String)
      @value = /^(?:#{@original})/
    end

    def to_str
      Str.new(@original)
    end

    # Any regex is true, as any regex (even an empty one)
    # matches something.
    def true?
      true
    end

    # Returns whether this regex is equal-by-value to the
    # *other* regex.
    def eqv?(other : MRegex)
      @value == other.value
    end

    # Returns whether this regex matches the *other* string.
    #
    # ```ven
    # ensure `12` in ["34", "56", "12"]
    # ```
    def eqv?(other : Str)
      @value === other.value
    end

    def length
      @original.size
    end

    def to_s(io)
      io << "`" << @original << "`"
    end
  end

  # Ven's range data type.
  struct MRange < MStruct
    # Maximum amount of values a range to vec conversion
    # can handle.
    RANGE_TO_VEC_CAP = 100_000

    # Returns the start of this range.
    getter start : Num
    # Returns the end of this range.
    getter end : Num

    # Contains the distance between the end of this range
    # and the start of this range.
    @distance : MNumberType

    def initialize(@start : Num, @end : Num)
      @distance = (@end.value - @start.value).abs + 1
    end

    # Converts this range to vector.
    #
    # Will raise ModelCastException if the resulting vector
    # will be too large (see `RANGE_TO_VEC_CAP`).
    def to_vec
      if @distance > RANGE_TO_VEC_CAP
        raise ModelCastException.new("range #{self} is too large to be a vector")
      end

      result = Vec.new

      # These will not overflow for there is RANGE_TO_VEC_CAP,
      # which is (at least, should be) much lower than max Int32.
      start = @start.to_i
      end_  = @end.to_i

      if start > end_
        start.downto(end_) { |it| result << Num.new(it) }
      elsif start < end_
        start.upto(end_) { |it| result << Num.new(it) }
      end

      result
    end

    def indexable?
      true
    end

    def eqv?(other : MRange)
      @start.eqv?(other.start) && @end.eqv?(other.end)
    end

    def field(name)
      case name
      when "start"
        @start
      when "end"
        @end
      when "empty?"
        MBool.new(@start.value == @end.value)
      end
    end

    def length
      @distance.to_i
    end

    def []?(index : Int)
      start = @start.value
      end_  = @end.value

      if index < 0
        # E.g., (1 to 10)(-1) is same as (10 to 1)(0);
        #       (10 to 1)(-1) is same as (1 to 10)(0).
        index = -index - 1
        start, end_ = end_, start
      end

      if start > end_
        # E.g., 10 to 1
        return unless (value = start - index) && value >= end_
      else
        # E.g., 1 to 10
        return unless (value = start + index) && value <= end_
      end

      Num.new(value)
    end

    def to_s(io)
      io << @start << " to " << @end
    end

    # Returns whether this range includes *num*.
    def includes?(num : MNumberType)
      num >= @start.value && num <= @end.value
    end
  end

  # The parent of all Class `Model`s (those that are stored
  # on the heap and referred by reference).
  abstract class MClass
    Suite.model_template?
  end

  # Ven's vector data type.
  class MVector < MClass
    getter items : Models

    # Makes a new vector from *items*.
    def initialize(@items = Models.new)
    end

    # :nodoc:
    def initialize(raw_items : Array(MClass) | Array(MStruct))
      @items = raw_items.map &.as(Model)
    end

    # Makes a new vector from *items*, but maps `type.new(item)`
    # for each item.
    #
    # ```
    # Vec.from([1, 2, 3], Num) # ==> [Num.new(1), Num.new(2), Num.new(3)]
    # ```
    def self.from(items, as type : Model.class)
      new(items.map { |item| type.new(item) })
    end

    delegate :[], :<<, :map, :each, :size, to: @items

    # Returns the length of this vector.
    def to_num
      Num.new(size)
    end

    def to_vec
      self
    end

    def true?
      size != 0
    end

    def callable?
      true
    end

    def indexable?
      true
    end

    # Returns whether each consequent item of this vector is
    # equal-by-value to the corresponding item of the *other*
    # vector.
    def eqv?(other : Vec)
      lv, rv = @items, other.items

      lv.size == rv.size && lv.zip(rv).all? { |li, ri| li.eqv?(ri) }
    end

    def length
      size
    end

    def []?(index : Int)
      @items[index]?
    end

    def []?(range : Range)
      @items[range]?.try { |subset| Vec.new(subset) }
    end

    def []=(index : Num, value : Model)
      return if size < (index = index.to_i)

      @items[index] = value
    end

    def to_s(io)
      io << "[" << @items.join(", ") << "]"
    end
  end

  # Ven's type data type. It represents other Ven data types.
  class MType < MClass
    # Returns the name of this type.
    getter name : String
    # Returns the `Model` class this type represents, e.g.,
    # `MVector`, `MString`.
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

    # Returns whether this function takes *type* as its
    # first (or *arhno*-th) parameter.
    def leading?(type : Model, argno = 0)
      false
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

    def leading?(type, argno = 0)
      type.match(@given[argno])
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
        Vec.from(params, Str)
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

    def leading?(type, argno = 0)
      @variants.any? &.leading?(type, argno)
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

    delegate :name, :field, :length, :specificity, to: @function

    def leading?(type)
      @function.leading?(type, @args.size - 1)
    end

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
    getter parent : MFunction
    getter namespace : Context::Machine::Scope

    def initialize(@parent, @namespace)
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

    # Sets *referent* field of this box instance to *value*.
    #
    # If *referent* is one of the typed fields (i.e., it was
    # declared as a box parameter and thus has a type), a
    # match against that type is performed.
    def []=(referent : Str, value : Model)
      field = referent.value

      return unless @namespace.has_key?(field)

      if (parent = @parent).is_a?(MBox)
        # Make sure the types match, if value's one of the
        # parameters, that is.
        typed_at = parent.params.index(field)

        if typed_at && !value.match(type = parent.given[typed_at])
          raise ModelCastException.new(
            "type mismatch in assignment to '#{field}': " \
            "expected #{type}, got #{value}")
        end
      end

      @namespace[field] = value
    end

    def to_s(io)
      io << "instance of " << @parent
    end
  end

  # Represents a Ven lambda (nameless function & closure).
  class MLambda < MFunction
    # Lambda has to have some name for compatibility with other
    # MFunctions.
    getter name = "lambda"
    # Returns the **surrounding** scope (singular!) of this
    # lambda. I.e., won't contain globals etc.
    getter scope : Context::Machine::Scope
    getter arity : Int32
    getter slurpy : Bool
    getter target : Int32
    getter params : Array(String)

    def initialize(@scope, @arity, @slurpy, @params, @target)
    end

    def variant?(args)
      self if (@slurpy && args.size >= @arity) || args.size == @arity
    end

    def to_s(io)
      io << "lambda " << "(" << params.join(", ") << ")"
    end
  end
end
