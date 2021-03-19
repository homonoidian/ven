module Ven::Suite
  # The struct that `Chunk`s use to represent symbols (Ven
  # symbols, that is) in data.
  struct Entry
    getter name : String
    getter nesting : Int32

    def initialize(@name, @nesting)
    end

    def to_s(io)
      io << @name << "#" << @nesting
    end
  end
end
