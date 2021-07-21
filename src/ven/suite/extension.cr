module Ven::Suite
  # An extension to Ven, made in Crystal.
  abstract class Extension
    # Casts `args[argno]` to *type*.
    #
    # Dies if unsuccessful.
    private macro as_type(argno, type)
      args[{{argno}}].as?({{type}}) || machine.die(
        "type mismatch for argument #{{{argno + 1}}}: " \
        "expected #{MType[{{type.resolve == Model ? MAny : type}}]}"
      )
    end

    # Yields with cast *argtypes* (of `TypeDeclaration`s) vars
    # cast to the corresponding types.
    #
    # ```
    # with_args(a : Str, b : Str) do
    #   ...
    # end
    # ```
    private macro with_args(argtypes)
      {% for argtype, index in argtypes %}
        {{argtype.var}} = as_type({{index}}, {{argtype.type}})
      {% end %}

      {{yield}}
    end

    # Yields a consesus builtin Proc. See `with_args` to see
    # what *argtypes* are.
    #
    # Converts block result to Model using `Adapter.to_model`.
    private macro in_builtin_proc(argtypes)
      ->(machine : Machine, args : Models) do
        Adapter
          .to_model(with_args({{argtypes}}) { {{ yield }}})
          .as(Model)
      end
    end

    # Returns an `MBuiltinFunction` named *name*. For yield
    # and *argtype* semantics, see `in_builtin_proc`.
    macro builtin(name, argtypes)
      MBuiltinFunction.new({{name}}, {{argtypes.size}},
        in_builtin_proc({{argtypes}}) do
          {{ yield }}
        end
      )
    end

    # Assigns *name* to *value* in the global scope. Notifies
    # the compiler.
    macro defglobal(name, value)
      {% if !name.is_a?(StringLiteral) %}
        {% name = name.stringify %}
      {% end %}
      c_context.bound({{name}})
      m_context[{{name}}] = {{value}}
    end

    # Defines a builtin *name* in *ns*. See `builtin`.
    #
    # If *ns* is nil, the global scope is assumed, and the
    # compiler is notified accordingly.
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

      {{ns}}[{{name}}] = builtin({{name}}, {{argtypes}}) do
        {{yield}}
      end
    end

    # Defines a generic named *name*. Each variant of *variants*
    # must be an `MFunction`. If *ns* is nil, the global scope
    # is assumed, and the compiler is notified accordingly.
    macro defgeneric(name, *variants, in ns = nil)
      {% if !name.is_a?(StringLiteral) %}
        {% name = name.stringify %}
      {% end %}

      {% if ns == nil %}
        # If not passed *ns*, assume it to be *m_context*. In
        # this case, also declare in the compiler context.
        {% ns = :m_context.id %}
        c_context.bound({{name}})
      {% end %}

      {{ns}}[{{name}}] =
        MGenericFunction.new({{ name }})
          {% for variant in variants %}
            .add({{variant}})
          {% end %}
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

    # Loads this extension into *m_context*, *c_context*.
    protected abstract def load(
      c_context : Context::Compiler,
      m_context : Context::Machine
    )
  end
end
