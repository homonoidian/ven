module Ven::Suite
  # The base class for a node (in Ven, quote) visitor.
  abstract class Visitor(T)
    setter last : Quote = QVoid.new

    # Remembers *quote* as the last visited quote, and hands
    # it off to `visit!`.
    def visit(quote : Quote)
      visit!(@last = quote)
    end

    # Maps `visit(quote)` on *quotes*.
    def visit(quotes : Quotes)
      quotes.map do |quote|
        visit(@last = quote).as(T)
      end
    end

    # Fallback visitor (subclass has no such visitor).
    def visit!(quote : _)
      raise InternalError.new("#{self.class}: could not visit: #{quote}")
    end
  end
end
