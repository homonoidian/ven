module Ven::Suite
  # The metadata a `Chunk` carries.
  abstract class Meta
  end

  # Void chunk metadata.
  class VoidMeta < Meta
  end

  # Function chunk metadata.
  class FunMeta < Meta
    # How many elements this function's 'given' appendix has.
    property given

    # How many arguments this function takes.
    property arity

    # Is this function slurpy?
    property slurpy

    # Parameters of this function (including the slurpie,
    # if any).
    property params

    def initialize
      @given = uninitialized Int32
      @arity = uninitialized Int32
      @slurpy = uninitialized Bool
      @params = uninitialized Array(String)
    end
  end
end
