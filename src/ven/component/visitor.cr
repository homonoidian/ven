module Ven
  abstract class Visitor
    last : Quote

    def visit(quote : Quote)
      visit!(@last = quote)
    end

    def visit(quotes : Quotes)
      quotes.map do |quote|
        visit(@last = quote)
      end
    end

    def visit!(quote : _)
      raise InternalError.new("could not visit: #{quote}")
    end
  end
end
