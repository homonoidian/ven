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

    def read(*args)
      @reader.read(*args)
    end

    def visit(*args)
      @machine.visit(*args)
    end

    # Load given *extensions*, a bunch of Component::Extension
    # subclasses.
    def load(*extensions : Component::Extension.class)
      extensions.each do |extension|
        extension.new(@context).load
      end
    end

    def feed(filename : String, source : String)
      tree = read(filename, source)

      visit(tree).last?
    end
  end
end
