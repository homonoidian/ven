module Ven::Suite::ParameterSuite
  # Holds Ven function/box parameter information at read-time
  # & compile-time.
  struct Parameter
    include JSON::Serializable

    # Consensus representation for a nameless parameter.
    NAMELESS = "<nameless>"

    # Returns the tag of this parameter.
    getter tag : QTag
    # Returns the index of this parameter.
    getter index : Int32
    # Returns the name of this parameter, unless it is nameless.
    getter name : String?
    # Returns the source quote of this parameter.
    getter source : Quote
    # Returns the given that corresponds to this parameter, if any.
    getter given : MaybeQuote
    # Returns whether this parameter is slurpy.
    getter slurpy = false
    # Returns whether this parameter is an underscore (`_`).
    getter underscore = false
    # Returns whether this parameter is a contextual.
    getter contextual = false
    # Returns the pattern if this parameter is a pattern
    # parameter, otherwise nil.
    getter pattern : MaybeQuote
    # Returns whether this parameter is restricted. In restricted
    # mode, only named parameters, slurpies, and pattern quotes
    # are allowed.
    getter restricted = false

    # Extracts the `Parameter` data given *parameter* and
    # *given*. If *parameter* is not a quote of one of the
    # parameter quote types, dies of read error.
    def initialize(@index, @source : Quote, @given = nil, @restricted = false)
      # Same as in `Quote`, same as in `FieldAccessor`: there
      # must be no QGroup in Quote's place. **Do not forget to
      # add an '||' or a 'case-when' when a new Quote-typed
      # instance variable is introduced!**.
      if given = @given.as?(QGroup)
        raise ReadError.new(given.tag, "got group where expression expected")
      end

      @tag = @source.tag

      # I do hate this loop very much, but I needed some
      # control flow!
      loop do
        case source = @source
        when QReadtimeSymbol, QReadtimeEnvelope
          # We trust `PFun`/`PBox` making sure that we're in
          # a readtime context, and thus wait for expansion.
          # *restricted* doesn't affect these two.
          break
        when QRuntimeSymbol
          @name = source.value
          unless @name.in?("*", "$") && restricted
            @slurpy = @name == "*"
            @contextual = @name == "$"
            break
          end
        when QSuperlocalTake
          break @underscore = true unless restricted
        when QPatternEnvelope, QLambda
          # Remember, patterns issue `QLambdas`. Before the
          # transform (say, at read time), it's a pattern
          # envelope, but after transform, it's a `QLambda`.
          break @pattern = source
        end

        raise ReadError.new(@tag, "invalid parameter quote")
      end
    end

    def clone
      self
    end
  end

  # A wrapper around an array array of parameters.
  struct Parameters
    include JSON::Serializable

    # Makes a new `Parameters` from *parameters*. Validates
    # (making sure there is only one '$', '*', and that '*'
    # is at the end), and dies of read error if unsuccessful.
    def initialize(@parameters : Array(Parameter))
      slurpie = false
      context = false

      # Will return {tag, error} if invalid, otherwise nil.
      invalid = @parameters.each_with_index do |parameter, index|
        case parameter
        when .slurpy
          if index != @parameters.size - 1
            break parameter.tag, "'*' must be at the end of the parameter list"
          elsif slurpie
            break parameter.tag, "more than one '*' unsupported"
          else
            slurpie = true
          end
        when .contextual
          if context
            break parameter.tag, "more than one '$' unsupported"
          else
            context = true
          end
        end
      end

      raise ReadError.new(*invalid) unless invalid.nil?
    end

    # Returns the names of the parameters. If there is no name,
    # falls back to `NAMELESS`.
    def names : Array(String)
      @parameters.map do |parameter|
        parameter.name || Parameter::NAMELESS
      end
    end

    # Returns whether there is a slurpie in this `Parameters`.
    def slurpy? : Bool
      @parameters.any?(&.slurpy)
    end

    # Returns the required parameters.
    def required : Parameters
      Parameters.new @parameters.reject(&.slurpy)
    end

    # Returns the givens of the parameters.
    def givens : Array(MaybeQuote)
      @parameters.map(&.given)
    end

    def clone
      self
    end

    forward_missing_to @parameters
  end
end

module Ven::Suite
  include ParameterSuite
end
