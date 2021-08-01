module Ven::Library
  class System < Extension
    on_load do
      # Contains the available actions' `initialize` methods
      # wrapped in Ven builtins. Use `actions.dir()` to display
      # the available actions. Supports actions having generic
      # `initialize`s.
      definternal "actions" do
        {% for action in BaseAction.subclasses %}
          {% news = action.methods.select(&.name.== :initialize) %}

          {% if news.size >= 1 %}
            %variants = [
              {% for new in news %}
                {% arity = new.args.size %}
                # Returns an `MNative(BaseAction)`, calling
                # `<action>#initialize` with the arguments
                # it received.
                MBuiltinFunction.new({{action}}.name, {{arity}}) do |machine, args|
                  MNative(BaseAction).new(
                    {{action}}.new(
                      {% for argno in 0...arity %}
                        as_type({{argno}}, {{new.args[argno].restriction}}),
                      {% end %}
                    )
                  )
                end,
              {% end %}
            ].uniq!(&.arity)

            defgeneric {{action}}.name, %variants, in: this
          {% end %}
        {% end %}

        # Returns **all** actions. As currently, there is no
        # way to check whether an action is enabled Ven-time.
        this["dir"] = builtin "dir", [] of Nop do
          # At this point, there are already going to
          # be 'actions' in the context.
          actions = machine.context["actions"].as(MInternal)

          actions.fields.values.reject do |action|
            # Reject self: no need to have 'dir' in the output.
            action.as?(MBuiltinFunction).try(&.name.== "dir")
          end
        end
      end

      # Submits an I/O action. See `BaseAction`, its subclasses,
      # and `BaseAction#submit`. This builtin is a wrapper for
      # `action.submit`). Rescues & dies of `ActionError`.
      defbuiltin "submit", action : MNative(BaseAction) do
        action.submit
      rescue error : ActionError
        machine.die(error.message || "action error")
      end

      # Returns whether an I/O action is allowed (i.e., enabled)
      defbuiltin "allowed?", action : MNative(BaseAction) do
        action.value.class.enabled
      end
    end
  end
end
