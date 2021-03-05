module Ven::Suite
  # The base class for a node (in Ven, quote) visitor.
  abstract class Visitor
    # Maximum amount of nested `visit` calls. This prevents
    # the Crystal 'very deep recursion' error with thousands
    # of entries jumpscaring a user. Since we're a visitor, we
    # have to handle recursion depth errors **well**. Release
    # builds allow higher visit depth.
    #
    # WHAT: per one *meaningful* visit the Ven infrastructure
    # may make over 10 internal calls; this expodes the call
    # stack very quickly, causing Ven itself to blow up
    # eventually. We prevent this by having a `MAX_VISIT_DEPTH`.
    MAX_VISIT_DEPTH =
      {% if flag?(:release) %}
        4096
      {% else %}
        2048
      {% end %}

    setter last : Quote = QVoid.new

    @depth = 0

    # Remembers *quote* as the last visited node and hands it
    # off to `visit!`. Makes sure visit depth does not exceed
    # `MAX_VISIT_DEPTH`.
    def visit(quote : Quote)
      if (@depth += 1) > MAX_VISIT_DEPTH
        raise InternalError.new(
          "max visit depth exceeded: got more than #{MAX_VISIT_DEPTH} " \
          "consequtive visit calls")
      end

      result = visit!(@last = quote)
      @depth -= 1

      result
    end

    # Same as `visit(quote)`, but iterates over *quotes*.
    def visit(quotes : Quotes)
      quotes.map { |quote| visit(quote).as(Model) }
    end

    # Fallback visitor (subclass has no such visitor).
    def visit!(quote : _)
      raise InternalError.new("could not visit: #{quote}")
    end
  end
end
