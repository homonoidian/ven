module Ven::Component
  # The interrupt raised when a 'next' expression evaluates.
  class NextInterrupt < Exception
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
end
