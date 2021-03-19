module Ven::Suite
  # The base class for a node (in Ven, quote) visitor.
  #
  # *T* is the type a visit must return.
  abstract class Visitor(T)
    setter last : Quote = QVoid.new

    # Remembers *quote* as the last visited node and hands it
    # off to `visit!`.
    def visit(quote : Quote) : T
      visit!(@last = quote)
    end

    # Same as `visit(quote)`, but iterates over *quotes*.
    def visit(quotes : Quotes) : Array(T)
      quotes.map do |quote|
        visit(@last = quote).as(T)
      end
    end

    # Fallback visitor (subclass has no such visitor).
    def visit!(quote : _)
      raise InternalError.new("could not visit: #{quote}")
    end
  end
end
