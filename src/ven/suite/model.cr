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

  # ModelClass is, in essence, `Model.class`.
  alias ModelClass = MClass.class | MStruct.class

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
    ANON_ANY      = 1
    ANY
    ANON_TYPE
    ABSTRACT_TYPE
    CONCRETE_TYPE
    ANON_VALUE
    VALUE
  end

  # :nodoc:
  macro model_template?
    # Yields with Union TypeDeclaration *joint* cast to its
    # subtypes. E.g., when *joint* is `foo : Model`, the block
    # will have *foo* cast to `MClass`, and then, separately,
    # to `MStruct`, available in its scope.
    #
    # When *joint* is `@foo : Model`, a block argument that will
    # specify the alternative name for `@foo` is required, as
    # instance variables are not redefinable.
    macro disunion(joint, &block)
      {% verbatim do %}
        {% if !joint.is_a?(TypeDeclaration) %}
          {% raise "disunion: joint must be TypeDeclaration" %}
        {% end %}

        {% joint_name = joint.var %}
        {% joint_type = joint.type.resolve %}
        {% joint_types = joint_type.union_types %}

        {% if !joint_type.union? || joint_types.size < 2 %}
          {% raise "disunion: joint must be a Union" %}
        {% end %}

        if {{joint_name}}.is_a?({{joint_types[0]}})
          {% if joint_name.is_a?(InstanceVar) %}
            {{*block.args}} = {{joint_name}}.as({{joint_types[0]}})
          {% else %}
            {{joint_name}} = {{joint_name}}.as({{joint_types[0]}})
          {% end %}

          {{yield}}
        {% for type in joint_types[1..-1] %}
          elsif {{joint_name}}.is_a?({{type}})
            {% if joint_name.is_a?(InstanceVar) %}
              {{*block.args}} = {{joint_name}}.as({{type}})
            {% else %}
              {{joint_name}} = {{joint_name}}.as({{type}})
            {% end %}

            {{yield}}
        {% end %}
        else
          false
        end
    {% end %}
    end

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

    # Converts (casts) this model into a `MMap`
    def to_map : MMap
      raise ModelCastException.new("could not convert to map: #{type?}")
    end

    # Returns whether this model is true.
    def true? : Bool
      true
    end

    # Returns whether this model is a false.
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

    # Returns whether this model is of the `MType` *other*,
    # or of any of *other*'s subtypes.
    #
    # ```ven
    # ensure 1 is num;
    # ensure "hello" is str;
    # ensure typeof is builtin; # directly of this type
    # ensure typeof is function; # of subtype: builtin is function
    # ```
    def is?(other : MType) : Bool
      o_model = other.model
      # Deconstruct ModelClass to ModelClass members, and
      # check them with `<=`.
      disunion(o_model : ModelClass) do
        self.class <= o_model
      end
    end

    # Returns whether this model is of the compound type *other*.
    # Delegates the implementation to `MCompoundType`.
    def is?(other : MCompoundType)
      other.is?(self)
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
    # Provides several fields itself (but prefers your fields
    # with the same name):
    #   * `callable?` returns whether this model is callable;
    #   * `indexable?` returns whether this model is indexable;
    #   * `crystal` returns the Crystal string representation
    #   for this model.
    #
    # Do not override this method. Override `field?` instead.
    def field(name : String) : Model?
      field?(name) ||
        case name
        when "callable?"
          MBool.new(callable?)
        when "indexable?"
          MBool.new(indexable?)
        when "crystal"
          Str.new(inspect)
        end
    end

    # Returns a field's value for this model, or nil if this
    # model has no such field.
    #
    # This method could  be overridden by a subclass. Then it
    # would support the following syntax:
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
    def field?(name : String)
    end

    # Returns the length of this model. Falls back to 1.
    def length : Int32
      1
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
        self[begin_.to_i..]?
      elsif end_ = range.end
        self[..end_.to_i]?
      end
    end

    # :ditto:
    def []?(index : Range) : Model?
    end

    # Provides the subordinate policy for this model. In other
    # words, a way to support the following syntax (also known
    # as access-assign):
    #
    # ```ven
    # foo[subordinate] = value
    # ```
    #
    # Where `foo` is this model.
    #
    # Returns nil if found no *subordinate* / has no support for
    # such subordinate.
    def []=(subordinate : Model, value : Model) : Model?
    end

    # Returns the `MType` of this model, or nil if could
    # not determine.
    #
    # Please override `type` instead; overriding `type?` may
    # cause unwanted fuckery.
    def type? : MType?
      type || MType[self.class]?
    end

    # Returns the `MType` of this model, or nil if could
    # not determine.
    def type : MType?
    end

    # Dies. The implementing classes may decide to override
    # handle to/from-JSON conversion.
    def to_json(json : JSON::Builder)
      raise ModelCastException.new("cannot convert #{self} to JSON")
    end

    macro inherited
      # Returns whether this model class is concrete (i.e.,
      # is not an abstract class/struct).
      def self.concrete?
        \{{!@type.abstract?}}
      end

      \{% if !@type.abstract? %}
        def_clone
      \{% end %}
    end
  end

  # The parent of all Struct `Model`s.
  abstract struct MStruct
    Suite.model_template?
  end

  # The parent of all Class `Model`s (those that are stored
  # on the heap and referred).
  abstract class MClass
    Suite.model_template?

    def to_s(io)
      io << self
    end
  end

  # A model that holds a *value* of type *T*.
  #
  # Forwards missing to *value*.
  #
  # Forwards operators `+`, `-`, `*`, `/` to *value*, and
  # wraps the result in `MValue(T)`.
  #
  # Forwards operators `<`, `>`, `<=`, `>=` to *value*, and
  # wraps the result in `MBool`.
  abstract struct MValue(T) < MStruct
    getter value : T

    def initialize(@value : T)
    end

    {% for operator in ["<", ">", "<=", ">="] %}
      # Applies `{{operator.id}}` to the value of this `MValue`,
      # and the value of the *other* `MValue`. Wraps the result
      # in `MBool`.
      def {{operator.id}}(other : MValue(T))
        MBool.new(@value {{operator.id}} other.value)
      end
    {% end %}

    {% for operator in ["+", "-", "*", "/"] %}
      # Applies `{{operator.id}}` to the value of this `MValue`,
      # and the value of the *other* `MValue`. Wraps the result
      # into the same `MValue` type as this `MValue`.
      def {{operator.id}}(other : MValue(T))
        \{{@type}}.new(@value {{operator.id}} other.value)
      end
    {% end %}

    def is?(other : MValue)
      @value == other.value
    end

    def to_s(io)
      io << @value
    end

    forward_missing_to @value
  end

  # Ven's number data type (type num).
  struct MNumber < MValue(BigDecimal)
    def initialize(@value)
    end

    def initialize(input : Number | String)
      @value = input.to_big_d
    end

    def to_num
      self
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

    # Writes a JSON number.
    def to_json(json : JSON::Builder)
      json.number(@value)
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

    # Writes a JSON bool.
    def to_json(json : JSON::Builder)
      json.bool(@value)
    end
  end

  # Ven's string data type (type str).
  #
  # Ven strings are immutable.
  struct MString < MValue(String)
    delegate :size, to: @value

    # Repeats the value of this string *n* times. Converts
    # *n* to Int32 (see `MNumber#to_i`).
    def *(n : Num)
      Str.new(@value * n.to_i)
    end

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

    # Assumes this string is a JSON value and parses it.
    #
    # Returns the corresponding value (may not be a map!)
    def to_map : Model
      MMap.json_to_ven(@value)
    rescue e : JSON::ParseException
      message = e.message.not_nil!
      # Un-capitalize the message: Ven does not capitalize
      # error messages.
      raise ModelCastException.new(
        "'%': improper JSON: #{message[0].downcase + message[1..]}")
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

    # Writes a JSON string.
    def to_json(json : JSON::Builder)
      json.string(@value)
    end
  end

  # Ven's regular expression data type (type regex).
  #
  # Ven regexes are immutable.
  struct MRegex < MStruct
    getter regex : Regex

    # Makes a new Ven regex from the given *regex*.
    def initialize(@regex)
      @stringy = @regex.to_s
    end

    # Makes a new Ven regex from the given *stringy*.
    #
    # Unless there is one already, prepends '^' to *stringy*.
    # This is done to make sure we're matching strictly from
    # the start of any given matchee.
    #
    # Raises `ModelCastException` if *stringy* is bad.
    def initialize(@stringy : String)
      @regex = /^(?:#{@stringy.lchop('^')})/
    end

    def to_str
      Str.new(@stringy)
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

  # Ven's vector data type (type vec).
  #
  # Ven vector is a model wrapper around a reference to an
  # Array (*items*). If necessary, mutate the *items*, not
  # your MVector.
  struct MVector < MStruct
    property items : Models

    # Makes a new vector from *items*.
    def initialize(@items = Models.new)
    end

    # :nodoc:
    def initialize(raw_items : Array)
      @items = raw_items.map &.as(Model)
    end

    # Concatenates this vector with the *other* vector.
    def +(other : Vec)
      Vec.new(@items + other.items)
    end

    # Repeats the items of this vector *n* times. Converts
    # *n* to Int32 (see `MNumber#to_i`).
    def *(n : Num)
      Vec.new(@items * n.to_i)
    end

    # Returns the length of this vector.
    def to_num
      Num.new(size)
    end

    def to_vec
      self
    end

    # Interprets this vector as a map. The vector may be of
    # two shapes: `[[k v], [k v], ...]`, or `[k v k v ...]`.
    # Raises `ModelCastException` if it is of any other shape.
    def to_map
      pairs = [] of {String, Model}

      if all? { |item| item.is_a?(Vec) && item.size == 2 }
        # This vector is of shape [[k v], [k v], ...].
        each do |item|
          key, val = item.as(Vec)
          # Convert to str so we don't have to deal
          # with mutable keys.
          pairs << {key.to_str.value, val}
        end
      elsif items.size.even?
        # This vector is of shape [k v k v ...]:
        in_groups_of(2, reuse: true) do |group|
          key, val = group[0].not_nil!, group[1].not_nil!
          # Convert to str so we don't have to deal
          # with mutable keys.
          pairs << {key.to_str.value, val}
        end
      else
        raise ModelCastException.new("'%': improper vector shape")
      end

      MMap.new(pairs.to_h)
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
      b = range.begin
      e = range.end

      # Crystal's range semantics differs a bit from Ven's,
      # so we even have to use `.reverse` in some cases (in
      # almost all negative ones, to be precise).
      #
      # But overall, it is safe to default to Crystal's,
      # and we do it in case we can't recognize the range.
      if b && e
        if (b.negative? && e.negative?) || b.negative?
          subset = @items.reverse[(-b - 1)..(-e - 1)]?
        end
      elsif b
        if b.abs > length - b.positive?.to_unsafe
          subset = Models.new
        elsif b.negative?
          subset = @items.reverse[(-b - 1)..]?
        end
      end

      Vec.new(subset || @items[range]? || return)
    end

    def []=(index : Num, value : Model)
      return if size < (index = index.to_i).abs

      @items[index] = value
    end

    def to_s(io)
      io << "[" << @items.join(", ") << "]"
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

    # Makes a **raw vector** from *items*. Raw vectors provide
    # direct access to *items*.
    def self.around(items)
      vec = new
      vec.items = items
      vec
    end

    # Writes a JSON array.
    def to_json(json : JSON::Builder)
      @items.to_json(json)
    end

    forward_missing_to @items
  end

  # Ven's umbrella range data type (type range).
  #
  # Ven ranges are immutable.
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

    # Returns the length of this range.
    def to_num
      Num.new(@distance)
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

    # Provides `.begin`, `.end`, `.empty?`, `.full?`, `beginless?`,
    # `endless?`. Otherwise, returns nil.
    def field?(name)
      case name
      when "begin"
        @begin
      when "end"
        @end
      when "empty?"
        MBool.new(@begin.value == @end.value)
      when "full?"
        MBool.new(true)
      when "beginless?", "endless?"
        MBool.new(false)
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

  # Ven's partial range datatype (`from 10`, `to 100`, etc.)
  struct MPartialRange < MRange
    # Returns the beginning of this range, if there is one.
    getter begin : Num?
    # Returns the end of this range, if there is one.
    getter end : Num?

    def initialize(from @begin = nil, to @end = nil)
    end

    # Provides `.begin` (unless beginless), `.end` (unless
    # endless),`.beginless?`, `.endless?`, `full?`. Otherwise,
    # returns nil.
    def field?(name)
      if @begin == nil
        return @end if name == "end"
      elsif @end == nil
        return @begin if name == "begin"
      end

      case name
      when "beginless?"
        MBool.new(@begin == nil)
      when "endless?"
        MBool.new(@end == nil)
      when "full?"
        MBool.new(false)
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

  # The value (or type) that represents anything (in other
  # words, the value that matches on anything.)
  #
  # If used as a compound type lead, it represents alternative:
  # `any(1, 2, str)`  means `1`, `2`, or `str`.
  struct MAny < MStruct
    def weight
      MWeight::ANY
    end

    def to_s(io)
      io << "any"
    end
  end

  # Ven's type for representing other data types + itself.
  struct MType < MStruct
    # An array that contains all instances of this class. Used
    # to provide `typeof` dynamically.
    @@instances = [] of self

    # Returns the name of this type.
    getter name : String
    # The `Model` this type represents, e.g., `Vec`, `Str`.
    getter model : ModelClass

    delegate :==, to: @name

    def initialize(@name, for @model)
      @@instances << self
    end

    # Checks whether *other* type stands for the same model
    # as this type, or for a subclass model.
    def is?(other : MType)
      o_name = other.name
      o_model = other.model

      @name == o_name || o_model == MType ||
        # Deconstruct ModelClass to ModelClass members, and
        # check with `<=`.
        disunion(o_model : ModelClass) do
          @model <= o_model
        end
    end

    def weight
      if @model.concrete?
        MWeight::CONCRETE_TYPE
      else
        MWeight::ABSTRACT_TYPE
      end
    end

    def to_s(io)
      io << "type " << @name
    end

    # Returns whether this type instance's model is an instance
    # of *other*, or is a child of *other*'s subclasses.
    def is_for?(other : ModelClass)
      disunion(other : ModelClass) do
        disunion(@model : ModelClass) do |model|
          other <= model
        end
      end
    end

    # Returns the `MType` instance for *model* if there is one,
    # otherwise nil.
    def self.[]?(for model : ModelClass)
      @@instances.find &.is_for?(model)
    end

    # Returns the `MType` instance for *model* if there is one,
    # otherwise raises.
    def self.[](for model : ModelClass)
      self.[model]? || raise "type not found: #{model}"
    end
  end

  # Ven's map (short for mapping) type. A thin wrapper around
  # Crystal's Hash.
  struct MMap < MStruct
    getter map : Hash(String, Model)

    def initialize(@map = {} of String => Model)
    end

    def to_num
      Num.new(length)
    end

    # Serializes this map into a JSON object. You can use
    # `json_to_ven` to deserialize it back.
    #
    # Dies if some value cannot be serialized.
    def to_str
      Str.new(@map.to_json)
    end

    # Returns the values in this map.
    def to_vec
      Vec.new(@map.values)
    end

    # Returns self.
    def to_map
      self
    end

    def indexable?
      true
    end

    # Returns whether the keys & values of this map are equal
    # to keys and values of *other* map.
    def is?(other : MMap)
      return false unless @map.size == other.size

      @map.each do |key, val|
        return false unless other.has_key?(key)
        return false unless val.is?(other[key])
      end

      true
    end

    # Accesses by key, and provides `.keys`, `.vals`.
    #
    # Otherwise, returns nil.
    def field?(name)
      return @map[name] if has_key?(name)

      case name
      when "keys"
        Vec.from(@map.keys, Str)
      when "vals"
        Vec.new(@map.values)
      end
    end

    def length
      @map.size
    end

    def []?(key : Str)
      @map[key.value]?
    end

    def []=(key : Str, value : Model)
      @map[key.value] = value
    end

    def to_s(io)
      io << "%{"
      map.join(io, ", ") do |kv, io|
        k, v = kv
        k.inspect(io)
        io << " "
        v.to_s(io)
      end
      io << "}"
    end

    # Writes a JSON object.
    def to_json(json : JSON::Builder)
      @map.to_json(json)
    end

    forward_missing_to @map

    # Uses *pull* to deserialize a JSON value (i.e., JSON -> Ven).
    #
    # Although it's defined on MMap, it can be used to deserialize
    # all other kinds of JSON values.
    def self.json_to_ven(pull : JSON::PullParser)
      case pull.kind
      when .null?
        result = MBool.new(!!pull.read_null)
      when .int?
        result = Num.new(pull.read_int)
      when .float?
        result = Num.new(pull.read_float)
      when .string?
        result = Str.new(pull.read_string)
      when .bool?
        result = MBool.new(pull.read_bool)
      when .begin_array?
        result = Vec.new
        # Recurse on the items.
        pull.read_array do
          result << json_to_ven(pull)
        end
      when .begin_object?
        result = MMap.new
        # Recurse on the object value. We're fine with the
        # key being a String.
        pull.read_object do |key|
          result[key] = json_to_ven(pull)
        end
      else
        raise ModelCastException.new("unknown JSON value")
      end

      result
    end

    # Deserializes *json* (i.e., JSON -> Ven).
    #
    # Although it's defined on MMap, it can be used to deserialize
    # all other kinds of JSON values.
    def self.json_to_ven(json : String)
      json_to_ven JSON::PullParser.new(json)
    end
  end

  # A compound type is a type paired with an array of alternative
  # content types/models. `is?`-matching is used to check whether
  # one of these alternatives match. `is?`-matching is also used
  # to match against compound types.
  #
  # ```ven
  # ensure [1, 2, 3] is vec(num);
  # ensure 1 x 1000 is vec(1);
  # ```
  class MCompoundType < MClass
    getter lead : Model
    getter contents : Models

    def initialize(@lead, @contents)
    end

    def is?(other : MType)
      other.model == MCompoundType || @lead.is?(other)
    end

    def is?(other : MCompoundType)
      return false unless @lead.is?(other.lead)
      return false unless @contents.size == other.contents.size

      @contents.zip(other.contents).all? { |my, its| my.is?(its) }
    end

    # Checks whether *subject* is of the head type, and its
    # contents (whatever this means) match the content types.
    def is?(subject : Model)
      return false unless subject.is?(@lead)

      lead = @lead.as?(MType).try &.model || MAny

      # .== seems to be the only working way to match, for
      # reasons unknown to me, and the type of *subject*
      # is broken & assumed to be MBool. Idk.
      case lead
      when .== MMap
        subject = subject.as(Model).as(MMap)

        # Whether the shape of the subject map nonstrictly
        # (in a 'some' way) matches the content map.
        @contents.any? do |content|
          return false unless content.is_a?(MMap)

          # Keys specified in the content map may be missing,
          # and keys not specified may be present. But all
          # those that are present & specified must be of the
          # expected type.
          subject.each do |subj_key, subj_value|
            next unless type = content.map[subj_key]?
            return false unless subj_value.is?(type)
          end

          true
        end
      when .== Vec
        subject = subject.as(Model).as(Vec)

        # Whether each item of the subject vector matches
        # any content.
        subject.all? do |item|
          @contents.any? do |content|
            item.is?(content)
          end
        end
      else
        # Compound root 'any' exists to represent general
        # alternative: `1 is any(1, str, vec)`. Compounds
        # with unsupported heads are mostly synonymous
        # to `any`.
        @contents.any? do |content|
          subject.is?(content)
        end
      end
    end

    def weight
      @lead.weight + @contents.sum(&.weight.value)
    end

    def to_s(io)
      io << "compound " unless @lead.is_a?(MAny)
      io << @lead << " of " << @contents.join(", or ")
    end
  end

  # Ven's umbrella function model. It is the parent of all
  # function models.
  abstract class MFunction < MClass
    # Returns the specificity of this function. Defaults to 0.
    abstract def specificity

    # Returns the variant of this function that can receive
    # *args*. Returns nil if found no matching variant.
    def variant?(args : Models)
      self
    end

    # Returns whether this function takes *type* as its
    # first (or *argno*-th) parameter.
    def leading?(type : Model, argno = 0)
      false
    end

    def callable?
      true
    end

    # Provides `.name`, `.specificity`. Otherwise, returns nil.
    def field?(name : String)
      case name
      when "name"
        Str.new(name?)
      when "specificity"
        Num.new(specificity)
      end
    end

    # Returns whether *givens* match *args* (using `is?`).
    #
    # Implements the underflow rule (if *givens* underflow
    # *args*, the last given of *givens* is used to cover
    # the remaining *args*).
    def match?(args : Models, givens : Models) : Bool
      args.zip?(givens) do |argument, given|
        return false unless argument.is?(given || givens.last)
      end

      true
    end

    # Pretty-prints *params* alongside *given*.
    def pretty(params : Array(String), given : Models)
      params.zip(given).map(&.join ": ").join(", ")
    end

    # Computes the specificity number for *params* and *weights*
    # using the consensus (agreed-upon) algorithm.
    def specificity(params : Array(String), weights : Array(MWeight))
      params.zip(weights).map do |param, weight|
        weight = weight.value
        # Anonymous parameters lose one weight point and
        # become ANON_<>:
        weight -= param.in?("*", "$", "_").to_unsafe
      end.sum
    end

    # Returns the name of this function if it has one,
    # orelse nil.
    def name?
      {% if @type.instance_vars.find(&.id.== :name) %}
        @name
      {% else %}
        to_s
      {% end %}
    end
  end

  # Ven's most essential function model.
  #
  # ```ven
  # fun add(a, b) = a + b;
  #
  # ensure add is concrete;
  # ```
  class MConcreteFunction < MFunction
    getter name : String
    getter arity : Int32
    getter given : Models
    getter slurpy : Bool
    getter target : Int32
    getter params : Array(String)

    def initialize(@name, @given, @arity, @slurpy, @params, @target)
    end

    # Returns the specificity of this concrete.
    def specificity
      super(@params, @given.map &.weight)
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

    # Provides `.arity`, `.slurpy?`, `params`. Otherwise,
    # delegates to `MFunction`.
    def field?(name)
      case name
      when "arity"
        Num.new(@arity)
      when "slurpy?"
        MBool.new(@slurpy)
      when "params"
        Vec.from(params, Str)
      else
        super
      end
    end

    def length
      @arity
    end

    def to_s(io)
      io << "concrete " << @name << "(" << pretty(@params, @given) << ")"
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

  # The function model that can invoke Crystal code (`Proc`)
  # from Ven.
  #
  # Can be a member of an `MGenericFunction`.
  class MBuiltinFunction < MFunction
    getter name : String
    getter arity : Int32
    getter callee : Proc(Machine, Models, Model)

    def initialize(@name, @arity, @callee)
    end

    def initialize(@name, @arity, &@callee : Machine, Models -> Model)
    end

    # Returns the specificity of this builtin.
    #
    # Note that in builtins, all arguments have the weight
    # of `MWeight::ANY` (onymous any).
    def specificity
      @arity * MWeight::ANY.value
    end

    def variant?(args)
      args.size == @arity ? self : false
    end

    # As builtins' argument types are basically `any`s, it
    # could be assumed that each may receive *type* too.
    #
    # Always returns true.
    def leading?(type)
      true
    end

    # Provides `.arity`. Otherwise, delegates to `MFunction`.
    def field?(name)
      case name
      when "arity"
        Num.new(@arity)
      else
        super
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

  # An abstract function model that supervises a list of
  # `MFunction`s.
  class MGenericFunction < MFunction
    getter name : String

    def initialize(@name)
      @variants = [] of MFunction
    end

    delegate :[], :size, to: @variants

    # Returns the specificity of this generic.
    #
    # Sums the specificities of its variants.
    def specificity
      @variants.map(&.specificity).sum
    end

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
    # supervises. Overwrites identical variant, if any.
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

    def field?(name)
      case name
      when "variants"
        Vec.new(@variants)
      else
        super
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

    delegate :name, :arity, :length, to: @function

    # Returns the specificity of this partial.
    #
    # The specificity of this partial is the specificity of
    # the provided arguments (often `MWeight::VALUE`s), and
    # the subset of parameters they correspond to.
    def specificity
      fn = @function

      if fn.responds_to?(:params)
        super(fn.params[..@args.size - 1], @args.map &.weight)
      else
        # Delegate to the function if it has not exported
        # any params.
        fn.specificity
      end
    end

    def variant?(args) : self?
      self if @function.variant?(@args + args)
    end

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

    # Returns the specificity of this box. Internally the
    # same as concrete.
    def specificity
      super(@params, @given.map &.weight)
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
      @name == other.name && params == other.params
    end

    def to_s(io)
      io << "box " << @name << "(" << pretty(@params, @given) << ")"
    end
  end

  # An instance of an `MBox`.
  #
  # Carries with it its own copy of Scope (`Context::Machine::Scope`),
  # called namespace. It allows to access & modify the entries
  # in that namespace through field access (`instance.field`).
  class MBoxInstance < MClass
    getter parent : MFunction
    getter namespace : Hash(String, Model)

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
    # Additionally, provides: `.parent`, which returns the
    # parent of this box, and `.fields`, which returns an
    # **unordered** vector of fields in this box.
    def field?(name)
      # Prefer the user's fields over internal fields.
      if value = @namespace[name]?
        return value
      end

      case name
      when "parent"
        @parent
      when "fields"
        Vec.from(@namespace.keys, Str)
      end
    end

    # Sets *subordinate* field of this box instance to *value*.
    #
    # If *subordinate* is one of the typed fields (i.e., it was
    # declared as a box parameter and thus has a type), a
    # match against that type is performed.
    def []=(subordinate : Str, value : Model)
      field = subordinate.value

      return unless @namespace.has_key?(field)

      if (parent = @parent).is_a?(MBox)
        # Make sure the types match (if the parameter-to-change
        # is typed).
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
      if p = @parent.as?(MBox)
        io << p.name << "("

        # First, display the parameters, rejecting the dummy
        # NAMELESS ones.
        params = p.params.reject(Parameter::NAMELESS)

        params.join(io, ", ") do |param, io|
          io << param << "=" << @namespace[param]
        end

        # Then, display the namespace entries. The order is so
        # specific so as to not confuse the user with odd name
        # positioning, i.e., the user probably expects parameters
        # to come first.
        @namespace.join(io, ", ") do |(name, value), io|
          # Exclude the parameters, we've already shown them.
          unless name.in?(params)
            io << name << "=" << value
          end
        end

        io << ")"
      else
        io << "instance of " << @parent
      end
    end
  end

  # Represents a Ven lambda (nameless function & closure).
  class MLambda < MFunction
    getter scope : Hash(String, Model)
    getter arity : Int32
    getter slurpy : Bool
    getter target : Int32
    getter params : Array(String)

    def initialize(@scope, @arity, @slurpy, @params, @target)
      @myselfed = false
    end

    # Returns the specificity of this lambda. Since lambdas
    # do not allow `given`, their parameter weights are all
    # `MWeight::ANY`s.
    def specificity
      super(@params, [MWeight::ANY] * @arity)
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

    # Provides `.params`, and `.slurpy?`. Delegates to
    # `MFunction` otherwise.
    def field?(name)
      case name
      when "params"
        Vec.from(@params, Str)
      when "slurpy?"
        MBool.new(@slurpy)
      else
        super
      end
    end

    def length
      @arity
    end

    def variant?(args)
      self if (@slurpy && args.size >= @arity) || args.size == @arity
    end

    def to_s(io)
      io << "lambda " << "(" << params.join(", ") << ")"
    end

    # Freezes this lambda (see `MFrozenLambda`)
    def freeze(parent : Machine)
      MFrozenLambda.new(parent, self)
    end
  end

  # A frozen lambda is an `MLambda` alongside a `Machine`.
  # That machine is isolated from the parent machine, and
  # provides (a) a safe way to call Ven code from Crystal,
  # and (b) a safe way to parallelize Ven code execution.
  class MFrozenLambda < MFunction
    def initialize(parent : Machine, @lambda : MLambda)
      @scope = @lambda.scope.clone.as(Hash(String, Model))
      @chunks = parent.chunks.as(Chunks)
    end

    delegate :variant?, :specificity, to: @lambda

    # Calls this lambda with *args*.
    def call(args : Models) : Model
      machine = Machine.new(@chunks, CxMachine.new)

      machine.frames = [
        # Suicide frame. If the interpreter hits it, it will
        # immediately return.
        Frame.new(ip: Int32::MAX - 1),
        # This lambda's frame of execution. It is initialized
        # with the lambda's arguments and the target chunk.
        #
        # Since this is the topmost frame on the frame stack,
        # it will start executing first.
        Frame.new(Frame::Label::Function, args, @lambda.target),
      ]

      # Put the lambda scope clone onto the scopes stack.
      machine.context.push(isolated: true, initial: @scope.clone)

      # Run! Disable the scheduler: *parent* is the one who
      # schedules stuff (?)
      machine.start(schedule: false).return!.not_nil!
    end

    # :ditto:
    def call(*args : Model)
      call(args.to_a.map &.as(Model))
    end

    # Returns self. Frozen lambdas do not need to be cloned.
    def clone
      self
    end

    def to_s(io)
      io << "frozen " << @lambda
    end

    forward_missing_to @lambda
  end

  # A kind of model that wraps around a Crystal object of
  # type *T*. It provides an in-Ven way to pass native Crystal
  # values around.
  class MNative(T) < MClass
    # Returns the value of this MNative.
    getter value : T

    def initialize(@value, @desc = "object")
    end

    def type
      MType.new("native #{@desc}", MNative(T))
    end

    def to_s(io)
      io << "native " << @desc
    end

    forward_missing_to @value
  end

  # MInternal is like an `MBoxInstance`, but it doesn't require
  # a parent (actually, it doesn't have one), and can be created
  # from Crystal only. For Ven, MInternal is read-only.
  class MInternal < MClass
    # Returns the fields of this MInternal.
    getter fields : Hash(String, Model)

    # Yields an empty hash of `String`s to `Model`s. Makes
    # it possible to access the values of that hash using Ven
    # field access.
    def initialize(@desc : String)
      yield @fields = {} of String => Model
    end

    def field?(name)
      case name
      when .in?(@fields.keys)
        @fields[name]
      else
        super
      end
    end

    def to_s(io)
      io << "internal " << @desc
    end
  end
end
