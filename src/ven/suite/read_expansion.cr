require "./*"

module Ven::Suite
  class ReadExpansion < Transformer
    @definitions : Hash(String, Quote)

    def initialize(@definitions)
    end

    # Given a *message*, dies of read error that is assumed
    # to be at the start of the current quote.
    def die(tag : QTag, message : String)
      raise ReadError.new(tag, message)
    end

    # Substitutes itself with the quote it was assigned.
    def transform!(q : QReadtimeSymbol)
      @definitions[q.value]? ||
        die(q.tag, "there is no readtime symbol named '$#{q.value}'")
    end
  end
end
