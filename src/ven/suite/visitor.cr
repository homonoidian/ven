module Ven::Suite
  # The base class for a node (in Ven, quote) visitor.
  #
  # `T` is the return type of each visitor (but may not
  # be enforced).
  abstract class Visitor(T)
    setter last : Quote = QVoid.new

    # Maps `visit(quote)` on *quotes*.
    def visit(quotes : Quotes)
      quotes.map do |quote|
        visit(@last = quote).as(T)
      end
    end

    # Remembers *quote* as the last visited quote, and hands
    # it off to `visit!` (which should be implemented by the
    # inheriting class).
    def visit(quote : Quote)
      visit!(@last = quote)
    end

    # Fallback visitor (raises interla 'no such visitor').
    def visit!(quote)
      raise InternalError.new("#{self.class}: could not visit: #{quote}")
    end
  end

  # The base class of a quote transformer.
  #
  # Note that quote transformers are mutative, that is, they
  # change the given quote in-place.
  abstract class Transformer
    # Maps `transform(quote)` on *quotes*.
    def transform(quotes : Quotes)
      quotes.map { |quote| transform(quote) }
    end

    # If one or multiple of *quote*'s fields are of type `Quote`,
    # applies itself recursively on these fields. If not, leaves
    # the fields untouched.
    #
    # Can be overridden to transform one quote, located no matter
    # how deep in the quote tree, but ignore all others.
    def transform(quote : Quote)
      {% begin %}
        case quote
        {% for subclass in Quote.subclasses %}
          when {{subclass}}
            {% for instance_var in subclass.instance_vars %}
              %field = quote.{{instance_var}}
              if %field.is_a?(Quote)
                quote.{{instance_var}} = transform(%field)
              end
            {% end %}
        {% end %}
        else
          raise "unreachable"
        end
      {% end %}

      # We always-always want to return a quote.
      quote
    end

    # Fallback case for `transform`. Called when a field
    # is of alien (non-Quote/s) type.
    def transform(other)
      other
    end
  end
end
