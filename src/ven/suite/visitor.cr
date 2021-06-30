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
    def transform(quotes : Quotes | FieldAccessors)
      quotes.map { |quote| transform(quote) }
    end

    # If one or multiple of *quote*'s fields are of type `Quote`,
    # applies itself recursively on those fields. If not, leaves
    # them untouched.
    #
    # Can be concretized to transform a particular kind of quote
    # with **high degree of control**. Note that in this case,
    # you will have to transform all subsequent fields yourself.
    #
    # However, **you almost certainly want a tail transform**
    # concretization instead (see `transform!`). A tail transform
    # runs after all fields of the given quote were transformed.
    def transform(quote : Quote)
      {% begin %}
        case quote
        {% for subclass in Quote.subclasses %}
          when {{subclass}}
            {% for instance_var in subclass.instance_vars %}
              {% if instance_var.type <= Quote ||
                      instance_var.type <= FieldAccessor ||
                      instance_var.type == Quotes ||
                      instance_var.type == FieldAccessors %}
                quote.{{instance_var}} =
                  transform(quote.{{instance_var}})
                    .as({{instance_var.type}})
              {% end %}
            {% end %}
        {% end %}
        end
      {% end %}

      # Apply tail transform (if there is one; otherwise,
      # *quote* will be returned untouched).
      transform!(quote).as?(Quote) || quote
    end

    def transform(accessor : FADynamic)
      accessor.class.new transform(accessor.access)
    end

    def transform(accessor : FABranches)
      accessor.class.new transform(accessor.access).as(QVector)
    end

    # As `Transformer` finds it hard to see box namespace
    # as a valid transform target, we have to manually
    # transform it.
    def transform!(q : QBox)
      q.namespace = q.namespace.to_h do |n, v|
        # Transform names and values of this box's
        # namespace recursively.
        {transform(n).as(QSymbol), transform(v)}.as({QSymbol, Quote})
      end
    end

    # Fallback case for tail transform. Returns *other*.
    def transform!(other)
      other
    end

    # Fallback case for `transform`. Called when a field
    # is of alien (non-Quote/s) type.
    def transform(other)
      other
    end
  end
end
