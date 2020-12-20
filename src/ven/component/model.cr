require "big"

module Ven::Component
  # A pseudo-exception, in the same way the currently absent
  # `ReturnException` and `QueueException` are. The 'pseudo-'
  # part means they do not always cause death (`Machine.die`).
  class ModelCastException < Exception
  end

  # :nodoc:
  alias Num = MNumber
  # :nodoc:
  alias Str = MString
  # :nodoc:
  alias Vec = MVector
  # :nodoc:
  alias TypedParameter = {String, MType}

  # The base class of Ven's value system and, therefore, the
  # root type of Ven's type system. Anything Ven can work with
  # is, and must be, a subclass of Model. In Ven, Model is known
  # as `any`. And curiously, since types are Models too (see
  # `MType`), `num is any` yields true, as well as `any is any`.
  abstract class Model
    property value

    def initialize(
      @value)
    end

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
      MVector.new([self])
    end

    # Returns a field's value for this model.
    def field(name : String) : Model?
      nil
    end
  end

  # A `Model` that does not embox one particular value.
  abstract class AbstractModel < Model
    @value : Nil

    def initialize
      @value = nil
    end
  end

  # Ven boolean (`bool`) model. Emboxes a Bool.
  class MBool < Model
    @value : Bool

    def to_s(io)
      io << @value
    end

    # Yields 1 if the boolean is true, 0 otherwise.
    def to_num
      MNumber.new(@value ? 1 : 0)
    end
  end

  # Ven number (`num`) model. Emboxes a BigRational, implementing
  # a trade-off: speed is exchanged for accuracy and high-levelness.
  # Accepts either a BigDecimal or an Int32, converting it into
  # a BigRational.
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

  # Ven string (`str`) model. Emboxes a Crystal String.
  class MString < Model
    @value : String

    def to_s(io)
      io << '"' << @value << '"'
    end

    # Produces either the length of this string (in case it
    # could not be parsed into a number), or the number that
    # this string was parsed into.
    def to_num
      MNumber.new(@value.to_big_d)
    rescue InvalidBigDecimalException
      MNumber.new(@value.size)
    end

    def to_str
      self
    end
  end

  # Ven vector (`vec`) model. In Ven's particular case, 'vector'
  # is just a fancy (and memorable) name for a list. It emboxes
  # an Array of Models. The elements of a vector in Ven realm
  # are called 'items'.
  class MVector < Model
    @value : Array(Model)

    def to_s(io)
      io << "[" << @value.join(", ") << "]"
    end

    # Returns the length of this array.
    def to_num
      MNumber.new(@value.size)
    end

    def to_vec
      self
    end
  end

  # Ven hole (`hole`) model. This model is the simplest kind of
  # AbstractModel; that is, it's a valueless model. It is produced
  # by several operations, but mainly by a condition that has no
  # truthy branch, e.g., `if (false) 0`, which yields a `hole`
  # ('else' branch is truthy but absent). Holes are actually
  # interpreted only in lambda spreads, where they mean 'do not
  # add this item to the resulting list'; when used anywhere else
  # they cause a death.
  class MHole < AbstractModel
    def to_s(io)
      io << "hole"
    end
  end

  # Ven type (`type`) model. Emboxes a type's name and the
  # `Model.class` this type represents. The latter will be used
  # by the interpreter in an `is_a?`-like call to check whether
  # a value is of this type or not. This also allows to use
  # Crystal's inheritance as the foundation for Ven's types
  # hierarchy.
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

  # A dummy model whose subclasses are various function models,
  # and whose purpose is to be an umbrella `function` type. It
  # allows a type check like `foo is function` to work without
  # the user having to think of `concrete`, `generic` and so on.
  class MFunction < AbstractModel
  end

  # A particular variant of a generic function, known as
  # `concrete` in Ven. Emboxes this variation's name, body
  # and `QTag`, as well as its *given* constraints. This
  # means that any function is constrained; it's just that
  # the default restrictions are weak (`any`), as opposed
  # to strong restrictions (`num`, `vec`, etc.)
  class MConcreteFunction < MFunction
    getter tag, name, params, constraints, body, slurpy

    @params : Array(String)

    def initialize(
        @tag : QTag,
        @name : String,
        @constraints : Array(TypedParameter),
        @body : Quotes,
        @slurpy : Bool)

      @params = @constraints.map(&.first)
    end

    # Returns true if any of this concrete's parameters is
    # constrained by `any`, or this concrete has no parameters,
    # or this concrete is slurpy.
    def general?
      @slurpy ||
      @params.empty? ||
      @constraints.any? { |given| given[1].type == Model }
    end

    def <=>(right : MConcreteFunction)
      params.size <=> right.params.size
    end

    def field(name)
      case name
      when "name"
        Str.new(@name)
      when "params"
        Vec.new(@params.map { |param| Str.new(param).as(Model) })
      when "slurpy?"
        MBool.new(@slurpy)
      when "general?"
        MBool.new(general?)
      end
    end

    def to_s(io)
      io << "concrete fun " << @name << "(" << @constraints.map(&.join(": ")).join(", ") << ")"
    end
  end

  # An abstract, callable entity that is a collection of concretes
  # (`MConcreteFunction`). In Ven, it is known as `generic`.
  # Emboxes the name of this generic and the collection itself,
  # an Array of concretes.
  class MGenericFunction < MFunction
    getter name

    def initialize(@name : String)
      @general = [] of MConcreteFunction
      @constrained = [] of MConcreteFunction
    end

    # Add a *concrete* variant of this generic function.
    # Overwrite if an identical concrete exists.
    def add(concrete : MConcreteFunction)
      if concrete.general?
        @general.each_with_index do |existing, index|
          if existing.params.size == concrete.params.size
            return @general[index] = concrete
          end
        end

        @general << concrete
        @general.sort! { |a, b| b <=> a }
      else
        @constrained.each_with_index do |existing, index|
          if existing.constraints == concrete.constraints
            return @constrained[index] = concrete
          end
        end

        @constrained << concrete
        @constrained.sort! { |a, b| b <=> a }
      end

      concrete
    end

    def concretes
      @constrained + @general
    end

    def field(name)
      case name
      when "name"
        Str.new(@name)
      when "concretes"
        Vec.new(concretes.map(&.as(Model)))
      end
    end

    def to_s(io)
      io << "generic fun " << @name << " with " << concretes.size << " concrete(s)"
    end
  end

  # Ven builtin function (`builtin`) type. The bridge from Crystal
  # to Ven. Emboxes the name of this builtin and a Crystal Proc,
  # which takes two arguments: the first for `Machine`, the other
  # for an Array of arguments (them being `Model`s), and returns
  # a Model.
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
