module Ven::Suite
  abstract class Interrupt < Exception
  end

  # The interrupt raised when a 'next' expression evaluates.
  class NextInterrupt < Interrupt
    getter args : Models
    getter target : String?

    def initialize(@target, @args)
    end

    def to_s(io)
      io << "next"

      unless @target.nil?
        io << " " << @target
      end
    end
  end

  # The interrupt raised when a statement-level 'return' evaluates.
  class ReturnInterrupt < Interrupt
    getter value : Model

    def initialize(@value)
    end

    def to_s(io)
      io << "return"
    end
  end
end
