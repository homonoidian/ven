module Ven::Suite
  # Holds Ven function parameter information at read-time
  # & compile-time.
  struct Parameter
    include JSON::Serializable

    # Returns the index of this parameter.
    getter index : Int32
    # Returns the name of this parameter.
    getter name : String
    # Returns the given of this parameter, if any.
    getter given : Quote?
    # Returns whether this parameter is slurpy.
    getter slurpy : Bool
    # Returns whether this parameter is contextual.
    getter contextual : Bool

    def initialize(@index, @name,
                   @given = nil,
                   @slurpy = false,
                   @contextual = false)
    end

    def clone
      self
    end
  end

  # Parameters represents an immutable array of parameters.
  #
  # It provides various methods to filter it.
  struct Parameters
    include JSON::Serializable

    def initialize(@params : Array(Parameter))
    end

    delegate :each,
      :reverse_each,
      :size,
      :empty?,
      :join,
      to: @params

    # Returns the names of the parameters.
    def names : Array(String)
      @params.map(&.name)
    end

    # Returns all slurpy parameters.
    def slurpies
      Parameters.new @params.select(&.slurpy)
    end

    # Returns the guaranteed parameters (those that consume
    # exactly one value, always).
    def guaranteed
      Parameters.new @params.reject(&.slurpy)
    end

    # Returns the givens of the parameters.
    def givens
      @params.select(&.given)
    end

    def clone
      self
    end
  end
end
