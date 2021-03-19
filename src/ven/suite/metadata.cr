module Ven::Suite::Metadata
  # All `Chunk`s support metadata, but not necessarily
  # provide it.
  #
  # The subclasses of this class are the valid kinds of
  # metadata.
  abstract class Meta
  end

  # Carried by a `Chunk` that provides no metadata.
  class Empty < Meta
  end

  # Carried by a `Chunk` that provides function metadata.
  class Function < Meta
    # How many elements this function's 'given' appendix has.
    property given : Int32

    # How many arguments this function takes.
    property arity : Int32

    # Is this function slurpy?
    property slurpy : Bool

    # Parameters of this function (including the slurpie, if any).
    property params : Array(String)

    def initialize
      @given = uninitialized Int32
      @arity = uninitialized Int32
      @slurpy = uninitialized Bool
      @params = uninitialized Array(String)
    end
  end
end
