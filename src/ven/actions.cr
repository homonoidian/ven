module Ven::Actions
  # An internal exception raised when there is an error performing
  # some action.
  class ActionError < Exception
  end

  # The base class of all actions Ven knows about.
  abstract struct BaseAction
    class_property enabled = false

    macro finished
      # Crystal didn't like bare `include` (undefined constant),
      # so let's wait til all constants are defined.
      include Suite
    end

    # Submits (evaluates, enacts) this action. This method
    # provides the permission mechanism, so do not override
    # it. Override `submit!` instead.
    def submit
      unless @@enabled
        name, category = self.class.name, self.class.category
        raise ActionError.new("#{name} not allowed: try passing '--with-#{category}'")
      end

      submit!
    end

    # Submits (evaluates, enacts) this action, if allowed.
    abstract def submit!

    # Returns the name of this action.
    def self.name
      raise "unimplemented"
    end

    # Returns the category of this action.
    def self.category
      raise "unimplemented"
    end

    # Returns `self`.
    def clone
      self
    end
  end

  # Prints to STDOUT.
  struct Say < BaseAction
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

    def self.name
      "Say"
    end

    def self.category
      "screen"
    end
  end

  # Asks for user input.
  struct Ask < BaseAction
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

    def self.name
      "Ask"
    end

    def self.category
      "screen"
    end
  end

  # Reads a file from the disk.
  struct Slurp < BaseAction
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

    def self.name
      "Slurp"
    end

    def self.category
      "disk"
    end
  end

  {% for name in ["Burp", "Write"] %}
    struct {{name.id}} < BaseAction
      @filename : String
      @content : String

      def initialize(filename : Str, content : Str)
        @filename = filename.value
        @content = content.value
      end

      def submit!
        File.write(@filename, @content, {% if name == "Burp" %} mode: "a" {% end %})
      end

      def self.name
        {{name}}
      end

      def self.category
        "disk"
      end
    end
  {% end %}
end
