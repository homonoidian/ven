module Ven
  abstract class Visitor
    last : Quote

    private class DeathException < Exception
      getter message

      def initialize(@message : String)
      end
    end

    abstract def die(message : String, scope : Scope)

    def visit(quote : Quote, scope)
      visit!(@last = quote, scope)
    rescue death : DeathException
      die(death.message.not_nil!, scope)
    end

    def visit(quotes : Quotes, scope)
      quotes.map do |quote|
        visit(@last = quote, scope)
      end
    rescue death : DeathException
      die(death.message.not_nil!, scope)
    end

    def visit!(quote : _, scope)
      raise InternalError.new("could not visit: #{quote}")
    end
  end
end
