module Ven::Component
  # The interrupt raised when a 'next' expression evaluates.
  class NextInterrupt < Exception
    getter target, args

    def initialize(
      @target : String?,
      @args : Models)
    end

    def to_s(io)
      io << "next"

      unless @target.nil?
        io << " " << @target
      end
    end
  end
end
