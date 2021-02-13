module Ven::Component
  # The base class for a node (in Ven, quote) visitor.
  abstract class Visitor
    setter last : Quote = QVoid.new

    # Remembers the *quote* as the last visited node, then
    # hands it off to `visit!`.
    private macro visit(quotes)
      unless (%this = {{quotes}}).is_a?(Array)
        @last = %this
      end

      visit!(%this)
    end

    # Same as `visit!(quote)`, but iterates over *quotes*.
    def visit!(quotes : Quotes)
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
