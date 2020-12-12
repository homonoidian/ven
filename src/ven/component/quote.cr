module Ven
  struct QTag
    getter file, line

    def initialize(
      @file : String,
      @line : Int32)
    end
  end

  abstract class Quote
    getter tag

    def initialize(
      @tag : QTag)
    end

    protected def pretty(io, block : Quotes)
      io << "{ " << block.join("; ") << " }"
    end
  end

  alias Quotes = Array(Quote)

  abstract class QAtom < Quote
    getter value

    def initialize(@tag,
      @value : String)
    end

    def to_s(io)
      io << @value
    end
  end

  class QSymbol < QAtom
  end

  class QString < QAtom
    def to_s(io)
      io << '"' << @value << '"'
    end
  end

  class QNumber < QAtom
  end

  class QVector < Quote
    getter items

    def initialize(@tag,
      @items : Quotes)
    end

    def to_s(io)
      io << "[" << @items.join(", ") << "]"
    end
  end

  class QUPop < Quote
    def to_s(io)
      io << "_"
    end
  end

  class QURef < Quote
    def to_s(io)
      io << "&_"
    end
  end

  class QUnary < Quote
    getter operator, operand

    def initialize(@tag,
      @operator : String,
      @operand : Quote)
    end

    def to_s(io)
      io << @operator << @operand
    end
  end

  class QBinary < Quote
    getter operator, left, right

    def initialize(@tag,
      @operator : String,
      @left : Quote,
      @right : Quote)
    end

    def to_s(io)
      io << @left << " " << @operator << " " << @right
    end
  end

  class QCall < Quote
    getter callee, args

    def initialize(@tag,
      @callee : Quote,
      @args : Quotes)
    end

    def to_s(io)
      io << @callee << "(" << @args.join(", ") << ")"
    end
  end

  class QAssign < Quote
    getter target, value

    def initialize(@tag,
      @target : String,
      @value : Quote)
    end

    def to_s(io)
      io << @target << " = " << @value
    end
  end

  class QIntoBool < Quote
    getter value

    def initialize(@tag,
      @value : Quote)
    end

    def to_s(io)
      io << "(" << @value << ")" << "?"
    end
  end

  class QReturnDecrement < Quote
    getter target

    def initialize(@tag,
      @target : String)
    end

    def to_s(io)
      io << @target << "--"
    end
  end

  class QReturnIncrement < Quote
    getter target

    def initialize(@tag,
      @target : String)
    end

    def to_s(io)
      io << @target << "++"
    end
  end

  class QBinarySpread < Quote
    getter operator, body

    def initialize(@tag,
      @operator : String,
      @body : Quote)
    end

    def to_s(io)
      io << "|" << @operator << "| " << @body
    end
  end

  class QLambdaSpread < Quote
    getter lambda, operand

    def initialize(@tag,
      @lambda : Quote,
      @operand : Quote)
    end

    def to_s(io)
      io << "|" << @lambda << "| " << @operand
    end
  end

  class QBlock < Quote
    getter body

    def initialize(@tag,
      @body : Quotes)
    end

    def to_s(io)
      io << "{ " << @body.join("; ") << " }"
    end
  end

  class QIf < Quote
    getter cond, suc, alt

    def initialize(@tag,
      @cond : Quote,
      @suc : Quote,
      @alt : Quote?)
    end

    def to_s(io)
      io << @cond << " => " << @suc
      io << " else " << @alt if @alt
    end
  end

  class QFun < Quote
    getter name, params, body, types

    def initialize(@tag,
      @name : String,
      @params : Array(String),
      @body : Quotes,
      @types : Quotes)
    end

    def to_s(io)
      io << "fun " << @name << "(" << @params.join(", ") << ") "
      unless @types.empty?
        io << "meaning " << @types.join(", ") << " "
      end
      pretty(io, @body)
    end
  end
end
