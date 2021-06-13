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

    # Fallback visitor (raises internal 'no such visitor').
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
    # Can be concretized to transform a particular kind of
    # quote, located no matter how deep in the quote tree,
    # while ignoring all others.
    def transform(quote : Quote)
      {% begin %}
        case quote
        {% for subclass in Quote.subclasses %}
          when {{subclass}}
            {% for instance_var in subclass.instance_vars %}
              # To cause a recursive transform, instance_var
              # should be either of Quote+, or of Quotes.
              {% if instance_var.type <= Quote || instance_var.type == Quotes %}
                quote.{{instance_var}} = transform(quote.{{instance_var}}).as({{instance_var.type}})
              {% end %}
            {% end %}
        {% end %}
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
