module Ven
  class Manager
    getter context

    def initialize(@file : String)
      @context = Context.new
    end

    # Load given of extensions. An extension is a subclass
    # of Extension (raw, not instance)
    def load(*extensions : Extension.class)
      extensions.each do |extension|
        extension.new(@context).load
      end
    end

    # Interpret `input`, which must be one or more lines of
    # source code. Return the result of the last evaluation
    def feed(input : String)
      Machine.run(Parser.from(@file, input), @context).last
    end
  end
end
