module Ven::Component
  # The base class of all built-in (that is, written in Crystal)
  # libraries. To get a feel of a real extension, see `Library::Core`
  # (src/ven/library/core.cr)
  abstract class Extension
    include Component

    def initialize(
      @context : Context)
    end

    # Defines a Ven variable. *name* is a String, and *value*
    # is a `Model`.
    # ```
    #   defvar("PI", Num.new(3.14))
    # ```
    macro defvar(name, value)
      @context.define({{name}}, {{value}})
    end

    # Defines a Ven type. *name* is a String, and *model* is
    # the `Model.class` the type 'matches' on, in other words,
    # the type to-be-defined represents.
    # ```
    #   deftype("num", Num)
    # ```
    macro deftype(name, model)
      defvar({{name}}, MType.new({{name}}, {{model}}))
    end

    # Registers (makes visible) a Ven builtin function. *name*,
    # a String, is the name of an existing, reachable Crystal
    # method (see `fun!`)
    # ```
    #     fun! greet, name : Str do |m|
    #        puts "Hi, #{name.value}!"
    #     end
    #
    #     def load
    #       defun("greet")
    #     end
    # ```
    macro defun(name)
      defvar({{name}}, MBuiltinFunction.new({{name}}, {{name.id}}))
    end

    # Defines a Crystal method, *name*, which returns a Proc
    # to-be-used by Ven as the implementation of a builtin
    # function. This returned proc performs an arity check and
    # a type check based on *takes*, a sequence of TypeDeclarations.
    # *block* is the block that will be executed after these checks,
    # and is the body of the builtin function. It must accept
    # (but not necessarily use) one argument, `Machine`. For a usage
    # example, see `defun`.
    macro fun!(name, *takes, &block)
      {% types = [] of Constant %}
      {% params = [] of Constant %}

      # Check that `takes` is a bunch of TypeDeclarations
      {% for take in takes %}
        {% unless take.is_a?(TypeDeclaration) %}
          {% raise "[critical]: expected type declaration" %}
        {% end %}

        {% types << take.type %}
        {% params << take.var %}
      {% end %}

      def {{name.id}}
        ->({{machine = block.args.first}} : Machine, args : Models) do
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

    # `load` is called when this extension is 'included'.
    # It is thus a reasonable place to define all top-level
    # things, i.e., the entities this extension exports.
    abstract def load
  end
end
