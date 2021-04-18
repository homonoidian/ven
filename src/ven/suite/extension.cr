module Ven::Suite
  # An extension to Ven, made in Crystal.
  abstract class Extension
    # Exports the definitions into *m_context*. Declares them
    # in *c_context*.
    protected abstract def load(
      c_context : Context::Compiler,
      m_context : Context::Machine
    )
  end

  # A DSL for quickly making Ven extensions.
  #
  # Assignments (`x = y`) are converted into Ven symbol
  # assignments.
  #
  # Omits '_' at the end of an assignment target, allowing
  # to name Ven symbols like Crystal keywords (`if_ = 1`).
  #
  # If there is an assignment to a `Path` (e.g., `foo = Bar`),
  # the appropriate `MType` is created.
  #
  # `def`s are converted into Ven builtins. Argument types
  # count; unspecified will default to `Model`. Unspecified
  # return type means return a `Model`. `Nil` return type
  # means return a Ven bool true. Return type T means return
  # `T.new(value_returned_by_def)`.
  macro extension(name, &block)
    class {{name}} < Extension
      def load(c_context, m_context)
        {% for expression in block.body.expressions %}
          {% if expression.is_a?(Assign) %}
            {% value = expression.value %}
            {% target = expression.target.stringify %}

            # Strip '_' to allow Crystal-keyword-like names
            # (e.g., `true_ = 1` will be bound to `true`,
            # false_ = 0` to `false`, etc.)
            {% if target.ends_with?("_") %}
              {% target = target[0...-1] %}
            {% end %}

            c_context.bound({{target}})

            {% if value.is_a?(Path) %}
              m_context[{{target}}] = MType.new({{target}}, {{value}})
            {% else %}
              m_context[{{target}}] = {{expression.value}}
            {% end %}
          {% elsif expression.is_a?(Def) %}
            {% name = expression.name.stringify %}
            {% args = expression.args %}
            {% body = expression.body %}
            {% arity = args.size %}
            {% return_type = expression.return_type %}

            c_context.bound({{name}})

            %callee = -> (machine : Machine, args : Models) do
              # Define a variable for each of the received
              # arguments. Note that here, we are already
              # sure that the amount of arguments is correct.
              {% for argument, index in args %}
                {% restriction = argument.restriction || Model %}

                {{argument.name}} = args[{{index}}]

                # Check if the argument has the type that was
                # specified by the extension.
                unless {{argument.name}}.is_a?({{restriction}})
                  machine.die(
                    "'#{{{name}}}': '{{argument.name}}' (no. #{{{index}} + 1}):" \
                    " expected {{restriction}}, found #{{{argument.name}}.class}")
                end
              {% end %}

              %result =
                begin
                  {{body}}
                end

              {% if return_type.is_a?(Path) && return_type.resolve == Nil %}
                MBool.new(true)
              {% elsif return_type %}
                {{return_type}}.new(%result)
              {% end %}

              # Cast to Model no matter what.
              .as(Model)
            end

            m_context[{{name}}] = MBuiltinFunction.new(
              {{name}},
              {{arity}},
              %callee
            )
          {% end %}
        {% end %}
      end
    end
  end
end
