module Ven
  class World
    getter reader, machine, context

    def initialize
      @reader = Reader.new
      @machine = Machine.new
      @context = Component::Context.new

      @reader.world = self
      @machine.world = self
    end

    def visit(*args)
      @machine.visit(*args)
    end

    # Loads given *extensions*, a bunch of Component::Extension
    # subclasses.
    def load(*extensions : Component::Extension.class)
      extensions.each do |extension|
        extension.new(@context).load
      end
    end

    # Reads and evaluates a String of *source* under the
    # filename *filename*.
    def feed(filename : String, source : String)
      @reader.read(filename, source) do |quote|
        visit(quote)
      end
    end
  end
end
