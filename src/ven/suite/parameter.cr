module Ven::Suite
  # Holds Ven function/box parameter information at read-time
  # & compile-time.
  struct Parameter
    include JSON::Serializable

    # Returns the index of this parameter.
    getter index : Int32
    # Returns the name of this parameter.
    getter name : String
    # Returns the given that corresponds to this parameter,
    # if any.
    getter given : Quote?
    # Returns whether this parameter is slurpy.
    getter slurpy : Bool
    # Returns whether this parameter is an underscore (`_`).
    getter underscore : Bool

    def initialize(
      @index, @name,
      @given = nil,
      @slurpy = false,
      @underscore = false
    )
    end

    def clone
      self
    end
  end

  # An immutable array of parameters.
  struct Parameters
    include JSON::Serializable

    def initialize(@contents : Array(Parameter))
    end

    # Returns the names of the parameters.
    def names : Array(String)
      @contents.map(&.name)
    end

    # Returns the slurpy parameters.
    def slurpies : Parameters
      Parameters.new @contents.select(&.slurpy)
    end

    # Returns the required parameters.
    def required
      Parameters.new @contents.reject(&.slurpy)
    end

    # Returns the givens of the parameters.
    def givens
      @contents.select(&.given)
    end

    def clone
      self
    end

    forward_missing_to @contents
  end
end
