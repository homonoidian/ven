module Ven::Component
  # The base class for a node (in Ven, quote) visitor.
  abstract class Visitor
    last : Quote

    # Remembers the *quote* as the last visited node, then
    # hands it off to `visit!`.
    def visit(quote : Quote)
      visit!(@last = quote)
    end

    # Same as `visit(quote)`, but iterates over *quotes*.
    def visit(quotes : Quotes)
      quotes.map do |quote|
        visit!(@last = quote)
      end
    end

    # Fallback visitor (subclass has no such visitor).
    def visit!(quote : _)
      raise InternalError.new("could not visit: #{quote}")
    end
  end
end
