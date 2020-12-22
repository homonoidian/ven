module Ven::Component
  # The location (filename and line number) of a `Quote`.
  struct QTag
    getter file, line

    def initialize(
      @file : String,
      @line : Int32)
    end
  end

  # The base class of all Ven AST nodes, which are called *quotes*
  # in Ven.
  abstract class Quote
    getter tag

    def initialize(
      @tag : QTag)
    end

    protected def pretty(io, block : Quotes)
      io << "{ " << block.join("; ") << " }"
    end
  end

  # :nodoc:
  alias Quotes = Array(Quote)

  # The base class of all literal quotes, that is, quotes
  # that only have a String *value*.
  abstract class QAtom < Quote
    getter value

    def initialize(@tag,
      @value : String)
    end

    def to_s(io)
      io << @value
    end
  end

  # A symbol (also known as identifier), e.g.: `foo-bar-12`,
  # `baz_quux?`, `bar!`.
  class QSymbol < QAtom
  end

  # A string, e.g., `"hello\nworld"`.
  class QString < QAtom
    def to_s(io)
      io << '"' << @value << '"'
    end
  end

  # A number, e.g.: `12.34`, `1234`.
  class QNumber < QAtom
  end

  # A vector, e.g., `[1, "a", [], quux]`.
  class QVector < Quote
    getter items

    def initialize(@tag,
      @items : Quotes)
    end

    def to_s(io)
      io << "[" << @items.join(", ") << "]"
    end
  end

  # The name (underscores pop) describes the semantic action.
  # Lexically `_`.
  class QUPop < Quote
    def to_s(io)
      io << "_"
    end
  end

  # The name (underscores reference) describes the semantic action.
  # Lexically `&_`.
  class QURef < Quote
    def to_s(io)
      io << "&_"
    end
  end

  # A unary operation, e.g.: `+1234`, `-"doe"`
  class QUnary < Quote
    getter operator, operand

    def initialize(@tag,
      @operator : String,
      @operand : Quote)
    end

    def to_s(io)
      io << @operator << (@operator =~ /\w+/ ? " " : "") << @operand
    end
  end

  # A binary operation, e.g.: `12 + 34`, `"hello" ~ "world"`.
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

  # A call, e.g., `foo(1, 2, 3)`.
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

  # An assignment, e.g., `x = y`.
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

  # The name (into boolean) describes the semantic action.
  # Syntactically an expression (precedence > assignment)
  # ending with a `?`: `1 + 2?`, `[1, 2, 3] is 2?`, but
  # `x = (false)?` satisfies `ensure x is false`.
  class QIntoBool < Quote
    getter value

    def initialize(@tag,
      @value : Quote)
    end

    def to_s(io)
      io << "(" << @value << ")" << "?"
    end
  end

  # The name describes the semantic action. Syntactically,
  # e.g., `foo--` (left-to-right: return *foo*, decrement).
  class QReturnDecrement < Quote
    getter target

    def initialize(@tag,
      @target : String)
    end

    def to_s(io)
      io << @target << "--"
    end
  end

  # The name describes the semantic action. Syntactically, e.g.,
  # `foo++` (left-to-right: return *foo*, increment).
  class QReturnIncrement < Quote
    getter target

    def initialize(@tag,
      @target : String)
    end

    def to_s(io)
      io << @target << "++"
    end
  end

  # The name describes the semantic action. Syntactically, e.g.,
  # `a.b.c` (access field *c* of field *b* of *a*).
  class QAccessField < Quote
    getter head, path

    def initialize(@tag,
      @head : Quote,
      @path : Array(String))
    end

    def to_s(io)
      io << "(" << @head << ")." << @path.join(".")
    end
  end

  # A binary spread, e.g.: `|+| [1, 2, 3]`, `|*| [5, 4, 3, 2, 1]`.
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

  # A lambda spread, e.g.:
  #  `|_ + 1| [1, 2, 3]` - lambda spread
  #  `|say(_)|: [1, 2, 3]` - iterative spread.
  class QLambdaSpread < Quote
    getter lambda, operand, iterative

    def initialize(@tag,
      @lambda : Quote,
      @operand : Quote,
      @iterative : Bool)
    end

    def to_s(io)
      io << "|" << @lambda << (@iterative ? "|: " : "| ") << @operand
    end
  end

  # A block (that is, a group of quotes), e.g., `{ 1; 2; 3 }`.
  class QBlock < Quote
    getter body

    def initialize(@tag,
      @body : Quotes)
    end

    def to_s(io)
      io << "{ " << @body.join("; ") << " }"
    end
  end

  # An inline (or spanning) *if* statement, e.g.:
  #  `if (true) 1 else 0`,
  #  `if (foo is num) true`.
  class QIf < Quote
    getter cond, suc, alt

    def initialize(@tag,
      @cond : Quote,
      @suc : Quote,
      @alt : Quote?)
    end

    def to_s(io)
      io << "("
      io << "if (" << @cond << ") " << @suc
      io << " else " << @alt if @alt
      io << ")"
    end
  end

  # A function definition, e.g.:
  #  `fun a = 10`,
  #  `fun a(x, y, z) = x + y + z`,
  #  `fun a(x, y) given num, str { y = +y; y ~ x }`,
  #  `fun a(x, *) = x`.
  class QFun < Quote
    getter name, params, body, given, slurpy

    def initialize(@tag,
      @name : String,
      @params : Array(String),
      @body : Quotes,
      @given : Quotes,
      @slurpy : Bool)
    end

    def to_s(io)
      # TODO: beautify?

      io << "fun " << @name << "(" << @params.join(", ")

      io << (@slurpy ? ", *) " : ") ")

      unless @given.empty?
        io << "given " << @given.join(", ") << " "
      end

      pretty(io, @body)
    end
  end

  # An ensure expression, e.g. the famous `ensure "hello" + "world" is 10`.
  class QEnsure < Quote
    getter expression

    def initialize(@tag,
      @expression : Quote)
    end

    def to_s(io)
      io << "ensure " << @expression
    end
  end
end
