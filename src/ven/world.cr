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

    # Load given *extensions*, a bunch of Component::Extension
    # subclasses.
    def load(*extensions : Component::Extension.class)
      extensions.each do |extension|
        extension.new(@context).load
      end
    end

    private macro read(filename, source)
      @reader.reset({{filename}}, {{source}}).module
    end

    private macro eval(tree)
      @machine.visit({{tree}})
    end

    def feed(filename : String, source : String)
      eval(read(filename, source)).last?
    end
  end
end
