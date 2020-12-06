module Ven
  class Trace
    getter tag, name, amount

    def initialize(@tag : QTag, @name : String)
      @amount = 0
    end

    def use
      @amount += 1
    end

    def unuse
      @amount -= 1
    end

    def ==(right : Trace)
      @tag == right.tag && @name == right.name
    end

    def to_s(io)
      io << "'" << @name << "' " << "(" << @tag.file << ":" << @tag.line << ")"
      io << ", which itself was called " << @amount << " times" if @amount > 1
    end
  end
end
