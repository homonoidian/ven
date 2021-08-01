module Ven
  # An annotation used to specify some meta about a subclass
  # of `BaseAction`.
  #
  # Conventionally, accepts two named arguments: *name* (of
  # String), the name of the action (your action will be in
  # builtin internal `actions.<name>`), and *category* (of
  # Symbol, used to generate the permission CLI flag).
  #
  # The only category for which there is no permission flag,
  # i.e., which is always enabled, is `:screen`.
  annotation Action
  end

  # An internal exception raised when there is an error performing
  # some action.
  class ActionError < Exception
  end

  # The base class of all actions Ven knows about.
  abstract class BaseAction
    class_property enabled = false

    macro finished
      # Crystal didn't like bare `include` (undefined constant),
      # so let's wait til all constants are defined.
      include Suite
    end

    macro inherited
      # Submits (evaluates, enacts) this action. This method
      # provides the permission mechanism, so do not override
      # it. Override `submit!` instead.
      def submit
        unless @@enabled
          # Get the category, and name, from the **inherited's**
          # `@type` annotation.
          {% name = @type.annotation(Action)[:name].downcase %}
          {% category = @type.annotation(Action)[:category].id.stringify %}

          raise ActionError.new(
            "#{{{name}}} not allowed: try with '--with-#{{{category}}}'")
        end

        submit!
      end
    end

    # Submits (evaluates, enacts) this action, if allowed.
    abstract def submit!
  end

  module Actions
    # Prints to STDOUT.
    @[Action(category: :screen, name: "Say")]
    class Say < BaseAction
      @payload : String

      def initialize(payload : Str)
        @payload = payload.value
      end

      def initialize(payload : Model)
        @payload = payload.to_s
      end

      # Prints *payload* to STDOUT.
      def submit! : Nil
        puts @payload
      end
    end

    # Asks for input.
    @[Action(category: :screen, name: "Ask")]
    class Ask < BaseAction
      # Everyone's Fancyline to use for asking about stuff.
      #
      # More functionality is coming, of course. If Ven uses
      # Fancyline, Ven should have complete integration with it.
      @@fancy = Fancyline.new

      @prompt : String

      def initialize(prompt : Str)
        @prompt = prompt.value
      end

      def initialize(prompt : Model)
        @prompt = prompt.to_s
      end

      # Prints the prompt to STDOUT, and waits for user input.
      # Returns the user input as `Str`.
      def submit! : Str
        answer = @@fancy.readline(@prompt, history: false)
        answer ? Str.new(answer) : raise ActionError.new("end-of-input")
      rescue Fancyline::Interrupt
        raise ActionError.new("interrupted")
      end
    end

    @[Action(category: :disk, name: "Slurp")]
    class Slurp < BaseAction
      @filename : String

      def initialize(filename : Str)
        @filename = filename.value
      end

      def submit!
        if File.file?(@filename)
          File.read(@filename)
        else
          raise ActionError.new("file not found: #{@filename}")
        end
      end
    end

    {% for name in ["Burp", "Write"] %}
      @[Action(category: :disk, name: {{name}})]
      class {{name.id}} < BaseAction
        @filename : String
        @content : String

        def initialize(filename : Str, content : Str)
          @filename = filename.value
          @content = content.value
        end

        def submit!
          File.write(@filename, @content, {% if name == "Burp" %} mode: "a" {% end %})
        end
      end
    {% end %}
  end
end
