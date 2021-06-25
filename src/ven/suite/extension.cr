module Ven::Suite
  # An extension to Ven, made in Crystal.
  abstract class Extension
    # Casts `args[argno]` to *type*.
    #
    # Dies if unsuccessful.
    private macro as_type(argno, type)
      args[{{argno}}].as?({{type}}) ||
        machine.die("wrong type for argument \##{{{argno + 1}}}")
    end

    # Yields with cast *argtypes*, a list of type declarations.
    #
    # ```
    # with_args(a : Str, b : Str) do
    #   ...
    # end
    # ```
    private macro with_args(*argtypes)
      {% for argtype, index in argtypes %}
        {{argtype.var}} = as_type({{index}}, {{argtype.type}})
      {% end %}

      {{yield}}
    end

    # Yields a consesus builtin Proc. See `with_args` for
    # what *argtypes* are.
    #
    # Converts block result to Model using `Adapter.to_model`.
    private macro in_builtin_proc(*argtypes)
      ->(machine : Machine, args : Models) do
        Adapter
          .to_model(with_args({{*argtypes}}) { {{ yield }}})
          .as(Model)
      end
    end

    # Returns an `MBuiltinFunction` named *name*. For yield
    # and *argtype* semantics, see `in_builtin_proc`.
    private macro builtin(name, *argtypes)
      MBuiltinFunction.new({{name}}, {{argtypes.size}},
        in_builtin_proc({{*argtypes}}) { {{ yield }} })
    end

    # Defines *name* to be *value* in the global scope. Notifies
    # the compiler about it.
    macro defglobal(name, value)
      {% if !name.is_a?(StringLiteral) %}
        {% name = name.stringify %}
      {% end %}
      c_context.bound({{name}})
      m_context[{{name}}] = {{value}}
    end

    # Defines a builtin named *name* in *ns*. See `builtin`.
    #
    # If *ns* is nil, the global scope is assumed, and compiler
    # is notified about *name*.
    macro defbuiltin(name, *argtypes, in ns = nil)
      {% if !name.is_a?(StringLiteral) %}
        {% name = name.stringify %}
      {% end %}

      {% if ns == nil %}
        # If not passed *ns*, assume it to be *m_context*. In
        # this case, also declare in the compiler context.
        {% ns = :m_context.id %}
        c_context.bound({{name}})
      {% end %}

      {{ns}}[{{name}}] = builtin({{name}}, {{*argtypes}}) do
        {{yield}}
      end
    end

    # Defines a global `MInternal` under *name*.
    macro definternal(name, &block)
      {% if block.body.is_a?(Expressions) %}
        {% body = block.body.expressions %}
      {% else %}
        {% body = [block.body] %}
      {% end %}

      {% if !name.is_a?(StringLiteral) %}
        {% name = name.stringify %}
      {% end %}

      defglobal({{name}}, MInternal.new do |this|
        {% for expression in body %}
          {% if expression.is_a?(Call) && expression.name == :defbuiltin %}
            {{expression.name}}({{*expression.args}}, in: this) {{expression.block}}
          {% end %}
        {% end %}
      end)
    end

    # Yields inside a consensus `load` method.
    macro on_load
      def load(c_context : CxCompiler, m_context : CxMachine)
        {{yield}}
      end
    end

    # Exports the definitions into *m_context*. Declares them
    # in *c_context*.
    protected abstract def load(
      c_context : Context::Compiler,
      m_context : Context::Machine
    )
  end
end
