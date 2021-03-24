require "big"

module Ven::Suite
  alias Static = Int32 | BigDecimal | String

  # Anything that an instruction references by offset is
  # thought of as payload.
  #
  # An abstraction that gives a payload identity is called
  # payload vehicle.
  #
  # There are various kinds of payloads: jump payloads, static
  # data payloads, etc.
  abstract struct Payload
    # Defines the appropriate getters and the initialize method
    # for this payload, keeping the order.
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
  #
  # It carries and defines the identity of a jump target.
  struct VJump < Payload
    carries target : Int32

    def ==(other : VJump)
      @target == other.target
    end

    def to_s(io)
      io << "to " << @target
    end
  end

  # The static data payload vehicle.
  #
  # It carries and defines the identity of static data: chunk
  # offsets, lengths, number and string values, and other
  # internal data.
  struct VStatic < Payload
    carries value : Static

    # Compares the values of this and *other* first by class,
    # and only then by the value itself.
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
  # It carries and defines the identity of a symbol, whose
  # nest and name are known at compile-time.
  struct VSymbol < Payload
    carries name : String, nest : Int32

    def ==(other : VSymbol)
      @name == other.name && @nest == other.nest
    end

    def to_s(io)
      io << "sym " << @name << "#" << @nest
    end
  end

  # The function payload vehicle.
  #
  # It carries and defines the identity of a function.
  #
  # It also provides a number of metadata entries: the names
  # of the parameters and the amount of them (arity), the amount
  # of values in the given appendix, and the slurpiness.
  struct VFunction < Payload
    carries name : String,
      target : Int32,
      params : Array(String),
      given : Int32,
      arity : Int32,
      slurpy : Bool

    def ==(other : VFunction)
      @name == other.name &&
        @target == other.target &&
        @params == other.params &&
        @given == other.given &&
        @arity == other.arity &&
        @slurpy == other.slurpy
    end

    def to_s(io)
      io << "fun " << @name << "@" << @target
    end
  end
end
