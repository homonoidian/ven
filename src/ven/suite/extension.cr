module Ven::Suite
  abstract class Extension
    abstract def load(context : Context)
  end

  macro extension(name, &)
    class {{name}} < Ven::Suite::Extension
      private macro defsym(symbol, value)
        \{% if !symbol.is_a?(StringLiteral) %}
          \{% symbol = symbol.stringify %}
        \{% end %}

        context[\{{symbol}}] = \{{value}}
      end

      def load(context)
        {{yield}}
      end
    end
  end
end
