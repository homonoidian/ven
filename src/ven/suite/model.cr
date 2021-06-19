require "big"

module Ven::Suite
  # Model casting (aka internal conversion) will raise this
  # exception on failure (e.g. if a string cannot be parsed
  # into a number.)
  class ModelCastException < Exception
  end

  # Model is the most generic Crystal type for Ven values.
  # All entities accessible from Ven must either inherit
  # `MClass` or `MStruct`, which `Model` is a union of.
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
    ANON_ANY   = 1
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

    # Returns whether this model is of the type *other*.
    #
    # ```ven
    # ensure 1 is num;
    # ensure "hello" is str;
    # ```
    def is?(other : MType) : Bool
      other.type.is_a?(MClass.class) \
        ? self.class <= other.type.as(MClass.class)
        : self.class <= other.type.as(MStruct.class)
    end

    # Returns whether this model is semantically equal to
    # the *other* model.
    #
    # The whole concept of semantic equality is rather bland
    # in Ven. Models are free to choose the way they identify
    # themselves, as well as compare one identity to another.
    def is?(other)
      other.is_a?(MAny)
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
    def []?(range : MFullRange) : Model?
      self[range.begin.to_i..range.end.to_i]?
    end

    # :ditto:
    def []?(range : MPartialRange) : Model?
      if begin_ = range.begin
        self[begin_.to_i...]?
      elsif end_ = range.end
        self[...end_.to_i]?
      end
    end

    # :ditto:
    def []?(index : Range) : Model?
    end

    # Provides set-referent semantics for this model. In
    # other words, a way to support the following syntax:
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

    # Returns a naive, one-way representation of this model.
    #
    # This representation includes the type of this model
    # followed by the string representation of its value.
    def to_json(json : JSON::Builder)
      json.object do
        json.field("type", \{{ @type.name.split("::").last.stringify }})
        json.field("value", to_s)
      end
    end
  end

  # The parent of all Struct `Model`s.
  abstract struct MStruct
    Suite.model_template?
  end

  # A model that holds a value of type *T*.
  abstract struct MValue(T) < MStruct
    getter value : T

    def initialize(@value : T)
    end

    def is?(other : MValue)
      @value == other.value
    end

    def to_s(io)
      io << @value
    end
  end

  # Ven's number data type (type num).
  struct MNumber < MValue(BigDecimal)
    def initialize(@value)
    end

    def initialize(input : Int | BigInt | Float | String)
      @value = input.to_big_d
    end

    def to_num
      self
    end

    def true?
      @value != 0
    end

    # Returns whether this number is in the given range.
    #
    # ```ven
    # ensure 1 is 1 to 10;
    # ensure 11 is not 1 to 10;
    # ```
    def is?(other : MRange)
      other.includes?(@value)
    end

    # Returns the Int32 version of this number.
    #
    # Raises `ModelCastException` on overflow.
    def to_i : Int32
      @value.to_i32
    rescue OverflowError
      raise ModelCastException.new("numeric overflow")
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

    # Returns whether this string matches the given regex.
    #
    # It is used only internally. Look for the implementation
    # of the in-language 'is' shown below in `binary` of `Machine`.
    #
    # ```ven
    # ensure "12" is `12+`;
    # ```
    def is?(other : MRegex)
      other.regex === @value
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
    getter regex : Regex

    # Makes a new Ven regex from the given *regex*.
    def initialize(@regex)
      @stringy = @regex.to_s
    end

    # Makes a new Ven regex from the given *stringy*.
    #
    # Safely prepends '^' to the *stringy*, unless there is
    # one there already; this is done to make sure we're
    # matching strictly from the start of any given matchee,
    # as opposed to Crystal's default of matching anywhere
    # within a matchee.
    def initialize(@stringy : String)
      @regex = /^(?:#{@stringy.lchop('^')})/
    end

    def to_str
      Str.new(@stringy)
    end

    # Any regex is true, as any regex (even an empty one)
    # matches something.
    def true?
      true
    end

    # Returns whether this regex is the same as the
    # *other* regex.
    def is?(other : MRegex)
      @regex === other.regex
    end

    # Returns whether this regexes' source is equal to the
    # contents of the *other* string.
    #
    # ```ven
    # ensure `12` is "12";
    # ensure `a+` is not "aaa";
    # ```
    def is?(other : Str)
      @stringy == other.value
    end

    def length
      @stringy.size
    end

    def to_s(io)
      io << "`" << @stringy << "`"
    end
  end

  # Ven's umbrella range data type.
  abstract struct MRange < MStruct
  end

  # Ven's full range datatype (`1 to 10`, `0 to 100`, etc.).
  struct MFullRange < MRange
    # Maximum amount of values a range->vec conversion
    # can handle.
    RANGE_TO_VEC_CAP = 100_000

    # Returns the beginning of this range.
    getter begin : Num
    # Returns the end of this range.
    getter end : Num

    # Contains the distance between the end of this range
    # and the start of this range.
    @distance : BigDecimal

    def initialize(from @begin : Num, to @end : Num)
      @distance = (@end.value - @begin.value).abs + 1
    end

    # Converts this range to vector.
    #
    # Raises ModelCastException if the resulting vector will
    # exceed `RANGE_TO_VEC_CAP`.
    def to_vec
      if @distance > RANGE_TO_VEC_CAP
        raise ModelCastException.new("range #{self} is too large to be a vector")
      end

      result = Vec.new

      # These will not overflow for there is RANGE_TO_VEC_CAP,
      # which is (at least, should be) much lower than max Int32.
      begin_ = @begin.to_i
      end_ = @end.to_i

      if begin_ > end_
        begin_.downto(end_) { |it| result << Num.new(it) }
      elsif begin_ < end_
        begin_.upto(end_) { |it| result << Num.new(it) }
      end

      result
    end

    def indexable?
      true
    end

    def is?(other : MRange)
      @begin.is?(other.begin) && @end.is?(other.end)
    end

    def field(name)
      case name
      when "begin"
        @begin
      when "end"
        @end
      when "empty?"
        MBool.new(@begin.value == @end.value)
      end
    end

    def length
      @distance.to_i
    end

    def []?(index : Int)
      begin_ = @begin.value
      end_ = @end.value

      if index < 0
        # E.g., (1 to 10)(-1) is same as (10 to 1)(0);
        #       (10 to 1)(-1) is same as (1 to 10)(0).
        index = -index - 1
        begin_, end_ = end_, begin_
      end

      if begin_ > end_
        # E.g., 10 to 1
        return unless (value = begin_ - index) && value >= end_
      else
        # E.g., 1 to 10
        return unless (value = begin_ + index) && value <= end_
      end

      Num.new(value)
    end

    def to_s(io)
      io << @begin << " to " << @end
    end

    # Returns whether this range includes *num*.
    def includes?(num : BigDecimal)
      num >= @begin.value && num <= @end.value
    end
  end

  # Ven's partial range datatype (e.g., `from 10`, `to 100`, etc.)
  struct MPartialRange < MRange
    # Returns the beginning of this range, if there is one.
    getter begin : Num?
    # Returns the end of this range, if there is one.
    getter end : Num?

    def initialize(from @begin = nil, to @end = nil)
    end

    def field(name)
      case name
      when "beginless?"
        MBool.new(@begin == nil)
      when "endless?"
        MBool.new(@end == nil)
      end
    end

    def to_s(io)
      @begin ? (io << "from " << @begin) : (io << "to " << @end)
    end

    # Returns whether this range includes *num*.
    def includes?(num : BigDecimal)
      @begin ? num >= @begin.not_nil!.value : num <= @end.not_nil!.value
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

    delegate :[], :<<, :all?, :any?, :map, :each, :size, to: @items

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
    # semantically equal to the corresponding item of the
    # *other* vector.
    def is?(other : Vec)
      size == other.size && @items.zip(other.items).all? { |my, its| my.is?(its) }
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

  # Ven's type for representing other data types + itself.
  class MType < MClass
    # Returns the name of this type.
    getter name : String
    # Returns the class of the `Model` this type represents;
    # e.g., `MVector`, `MString`.
    getter type : MStruct.class | MClass.class

    delegate :==, to: @name

    def initialize(@name, @type)
    end

    # Returns whether this type represents the same model as
    # the other type.
    def is?(other : MType)
      @type == other.type
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
    def is?(other)
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

    # Returns whether *givens* match *args* (using `is?`).
    #
    # Implements the underflow rule (if *givens* underflow
    # *args*, the last given of *givens* is used to cover
    # the rest of the *args*).
    def match?(args : Models, givens : Models) : Bool
      args.zip?(givens) do |argument, given|
        return false unless argument.is?(given || givens.last)
      end

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
      return unless match?(args, @given)

      self
    end

    def leading?(type, argno = 0)
      type.is?(@given[argno])
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
        return false unless our.is?(their)
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

    def variant?(args) : self?
      return unless args.size == @arity
      return unless match?(args, @given)

      self
    end

    # Returns whether this box is equal to the *other* box.
    #
    # Just compares the names of the two.
    #
    # ```ven
    # box A;
    # box B;
    #
    # ensure A is not B;
    # ```
    def is?(other : MBox)
      same?(other)
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
    getter namespace : CxMachine::Scope

    def initialize(@parent, @namespace)
    end

    # Returns whether this box instance is equal to the *other*
    # box instance.
    #
    # This box instance and the *other* box instance are
    # considered equal if their parents are equal, and if
    # their hashes are equal.
    #
    # ```ven
    # box A;
    # box B;
    #
    # a = A();
    # b = B();
    #
    # ensure a is a;
    # ensure b is b;
    # ensure a is not b;
    # ensure b is not a;
    # ```
    def is?(other : MBoxInstance)
      @parent.is?(other.parent) && hash == other.hash
    end

    # Returns whether this box instance is parented by the
    # given box.
    #
    # ```ven
    # box A;
    #
    # a = A();
    #
    # ensure a is A;
    # ```
    def is?(other : MBox)
      @parent.is?(other)
    end

    # Returns one of the fields in the namespace of this box
    # instance.
    #
    # Additionally, provides two other fields: `.name`, which
    # returns the name of this box, and `.parent`, which returns
    # the parent of this box.
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

        if typed_at && !value.is?(type = parent.given[typed_at])
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
    getter scope : CxMachine::Scope
    getter arity : Int32
    getter slurpy : Bool
    getter target : Int32
    getter params : Array(String)

    def initialize(@scope, @arity, @slurpy, @params, @target)
      @myselfed = false
    end

    # Sets the name this lambda knows itself under.
    #
    # This method only works once, i.e., if the name is not
    # already there.
    #
    # This is useful to make recursive lambdas (when they're
    # the value of an assignment).
    def myself=(name : String)
      unless @myselfed
        @scope[name] = self
        @myselfed = true
      end
    end

    def variant?(args)
      self if (@slurpy && args.size >= @arity) || args.size == @arity
    end

    def to_s(io)
      io << "lambda " << "(" << params.join(", ") << ")"
    end
  end
end
