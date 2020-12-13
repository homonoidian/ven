module Ven
  abstract class Extension
    def initialize(
      @context : Context)
    end

    # Define a variable
    macro defvar(name, value)
      @context.define({{name}}, {{value}})
    end

    # Define a type. `model` is the model this type represents
    macro deftype(name, model)
      defvar({{name}}, MType.new({{name}}, {{model}}))
    end

    # Define a builtin function. `name` must be an existing
    # method that returns a Proc; class-level `defun` could
    # help to define this method
    macro declare(name)
      defvar({{name}}, MBuiltinFunction.new({{name}}, {{name.id}}))
    end

    # Define a Crystal method `name` that returns a Proc.
    # This Proc knows how to handle Ven calls properly.
    # `takes` is one or more type declarations. `block`
    # is a block that takes one argument, Machine
    macro defun(name, *takes, &block)
      {% types = [] of Constant %}
      {% params = [] of Constant %}

      # Check that `takes` is a bunch of TypeDeclarations
      {% for take in takes %}
        {% unless take.is_a?(TypeDeclaration) %}
          {% raise "expected type declaration" %}
        {% end %}

        {% types << take.type %}
        {% params << take.var %}
      {% end %}

      def {{name.id}}
        ->({{machine = block.args.first}} : Machine, args : Array(Model)) do
          # Check if got enough arguments
          if args.size < {{arity = params.size}}
            {{machine}}.die(
              "builtin '#{{{name}}}' expected #{{{arity}}} " \
              "or more arguments, got: #{args.size}")
          end

          # Define a variable for every parameter. Check that
          # the actual and the expected types match
          {% for param, index in params %}
            {{param}} = args[{{index}}]

            unless {{param}}.is_a?({{types[index]}})
              {{machine}}.die(
                "argument no. #{{{index + 1}}}, which was passed " \
                "to builtin '#{{{name}}}', is of an unexpected type")
            end
          {% end %}

          # Do the block
          {{yield}}.as(Model)
        end
      end
    end

    # defvar, deftype and declare all should be situated in `load`
    abstract def load
  end
end
