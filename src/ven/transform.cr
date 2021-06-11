module Ven
  # > There are things in this world which are easier worked
  # > with when you transform them, than when you try to deal
  # > with them virgin.
  #
  # This is the to-do second stage of Ven interpretation. It
  # will transform QPatterns into QLambdas, expand protocol
  # macros (e.g., `|a| b` into `spread((_) a, b)`), etc. Maybe
  # something else, too. Or nothing at all.
  class Transform < Ven::Suite::Transformer
    include Suite

    # Makes an instance of this class, transforms *quotes* with
    # it **in-place**, and disposes the instance immediately
    # afterwards.
    #
    # Returns the transformed quotes (although they are mutated
    # in-place anyways).
    def self.transform(quotes : Quotes)
      new.transform(quotes)
    end
  end
end
