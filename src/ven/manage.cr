module Ven
  class Manager
    getter context

    def initialize(@file : String)
      @context = Component::Context.new
    end

    # Load given *extensions*, a bunch of Component::Extension
    # subclasses.
    def load(*extensions : Component::Extension.class)
      extensions.each do |extension|
        extension.new(@context).load
      end
    end

    # Interpret `input`, which must be one or more lines of
    # source code. Return the result of the last evaluation.
    def feed(input : String)
      Machine.run(Ven.read(@file, input), @context).last?
    end
  end
end
