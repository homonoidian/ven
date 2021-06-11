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
    def transform(q : QReadtimeSymbol)
      @definitions[q.value]? ||
        die(q.tag, "there is no readtime symbol named '$#{q.value}'")
    end

    # A special-case of transparent transform, for box.
    #
    # `Transformer` finds it hard to see box namespaces as
    # valid transform targets.
    def transform(q : QBox)
      q.name = transform(q.name).as(QSymbol)
      q.namespace = q.namespace.to_h do |name, value|
        {transform(name).as(QSymbol),
         transform(value)}
      end
      q # How disgusting this lonely q is!
    end
  end
end
