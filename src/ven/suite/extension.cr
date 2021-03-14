module Ven::Suite
  # An extension to Ven, made in Crystal.
  abstract class Extension
    # Exports into *context* all entities that this extension
    # defined.
    abstract def load(context : Context)
  end

  # A DSL macro for quickly making an `Extension`.
  macro extension(name, &)
    class {{name}} < Ven::Suite::Extension
      private macro defsym(symbol, value)
        \{% if !symbol.is_a?(StringLiteral) %}
          \{% symbol = symbol.stringify %}
        \{% end %}

        context[\{{symbol}}] = \{{value}}
      end

      private macro die(*args)
        machine.die(\{{*args}})
      end

      private macro defun(name, *args, &)
        %name = \{{name}}
        %arity = \{{args.size}}
        %callee = ->(machine : Machine, got : Models) do
          \{% for argument, index in args %}
            \{{argument}} = got[\{{index}}]
          \{% end %}

          \{{yield}}.as(Model)
        end

        context[%name] = MBuiltinFunction.new(%name, %arity, %callee)
      end

      def load(context)
        {{yield}}
      end
    end
  end
end
