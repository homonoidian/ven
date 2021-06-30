require "./*"

module Ven::Suite
  class ReadExpansion < Transformer
    @definitions : Hash(String, Quote)

    def initialize(@definitions)
    end

    # Substitutes itself with the quote it was assigned.
    def transform!(q : QReadtimeSymbol)
      @definitions[q.value]? ||
        die("there is no readtime symbol named '$#{q.value}'")
    end
  end
end
