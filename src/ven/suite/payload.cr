require "big"

module Ven::Suite
  alias Static = Int32 | BigDecimal | String

  # A payload is a remotely stored argument of an instruction.
  # The instruction references it by specifying its offset in
  # the appropriate storage.
  #
  # Payload vehicles are thin wrappers around the payload. They
  # may provide additional information about the payload.
  abstract struct PayloadVehicle
    # Generates getters, and initialize method parameters,
    # from *props* of `TypeDeclaration`s.
    macro carries(*props)
      {% for prop in props %}
        getter {{prop}}
      {% end %}

      def initialize(
        {% for prop in props %}
          @{{prop.var}},
        {% end %})
      end
    end
  end

  # The jump payload vehicle.
  struct VJump < PayloadVehicle
    carries target : Int32

    def ==(other : VJump)
      @target == other.target
    end

    def to_s(io)
      io << "to " << @target
    end
  end

  # The static payload vehicle.
  #
  # It can carry chunk offsets, lengths, number and string
  # values, etc. See `Static`.
  struct VStatic < PayloadVehicle
    carries value : Static

    # Compares the values of this and *other* first by class,
    # and only then by value.
    def ==(other : VStatic)
      @value.class == other.value.class && @value == other.value
    end

    def to_s(io)
      io << "static "

      case @value
      in Int32
        io << "i32 " << @value
      in BigDecimal
        io << "num " << @value
      in String
        @value.inspect(io)
      end
    end
  end

  # The symbol payload vehicle.
  #
  # It carries a symbol, whose name and (possibly) nest are
  # known at compile-time.
  struct VSymbol < PayloadVehicle
    carries name : String, nest : Int32

    @nest = -1

    def ==(other : VSymbol)
      @name == other.name && @nest == other.nest
    end

    def to_s(io)
      io << "sym " << @name << "#" << @nest
    end

    # Makes a nameless VSymbol.
    def self.nameless
      new("<nameless>", -1)
    end
  end

  # The function payload vehicle.
  #
  # - `VFunction#symbol`: the `VSymbol` of this function;
  # - `VFunction#target`: the target chunk of this function;
  # - `VFunction#params`: an array of parameters of this function;
  # - `VFunction#given`: the amount of `given` values this function expects;
  # - `VFunction#arity`: the minimum amount of arguments required;
  # - `VFunction#slurpy`: whether this function is slurpy.
  struct VFunction < PayloadVehicle
    carries symbol : VSymbol,
      target : Int32,
      params : Array(String),
      given : Int32,
      arity : Int32,
      slurpy : Bool

    def ==(other : VFunction)
      @symbol == other.symbol &&
        @target == other.target &&
        @params == other.params &&
        @given == other.given &&
        @arity == other.arity &&
        @slurpy == other.slurpy
    end

    def to_s(io)
      io << "fun " << @symbol << "@" << @target
    end
  end
end
