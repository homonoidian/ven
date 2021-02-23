module Ven::Component
  # The interrupt raised when a 'next' expression evaluates.
  class NextInterrupt < Exception
    getter scope, args

    def initialize(
      @scope : String?,
      @args : Models)
    end

    def to_s(io)
      io << "next"

      unless @scope.nil?
        io << " " << @scope
      end
    end
  end
end
