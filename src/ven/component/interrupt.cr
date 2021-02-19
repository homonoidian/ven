module Ven::Component
  class NextInterrupt < Exception
    getter scope, args

    def initialize(
      @scope : String?,
      @args : Models)
    end
  end
end
