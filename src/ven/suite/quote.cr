module Ven::Suite
  # The location (*file*name and *line*number) of a `Quote`.
  struct QTag
    getter file : String
    getter line : UInt32

    def initialize(@file, @line)
    end

    # Returns a void tag.
    def self.void
      new("<void>", 1_u32)
    end

    # Returns whether this tag is equal to the *other* tag.
    def ==(other : QTag)
      @file == other.file && @line == other.line
    end
  end

  # The base class of all Ven AST nodes, which are called
  # **quotes** in Ven.
  abstract class Quote
    macro inherited
      macro defquote!(*fields)
        getter tag : QTag
        getter \{{*fields.map(&.var.id)}}

        def initialize(@tag,
          \{% for field in fields %}
            @\{{field}},
          \{% end %})
        end

        # Fallback pretty-printing.
        def to_s(io)
          io << "(" << {{@type.name.split("::").last}}

          \{% if !fields.empty? %}
            \{% for field in fields %}
              %field = \{{field.var}}

              %field.is_a?(Array) \
                ? io << " " << "[" << %field.join(" ") << "]"
                : io << " " << %field
            \{% end %}
          \{% end %}

          io << ")"
        end
      end
    end
  end

  # :nodoc:
  alias Quotes = Array(Quote)

  # Defines a *quote* with *fields*, which are `TypeDeclaration`s.
  private macro defquote(quote, *fields)
    class {{quote}} < Quote
      defquote!({{*fields}})
    end
  end

  # Passes `defquote` a *quote* and a field `value : String`.
  private macro defvalue(quote)
    defquote({{quote}}, value : String)
  end

  # A dummy Quote that can be used to experiment with the
  # Reader without writing a dedicated Quote first.
  class QVoid < Quote
    getter tag

    def initialize
      @tag = QTag.void
    end

    def to_s(io)
      io << "<void quote>"
    end
  end

  defvalue(QSymbol)
  defvalue(QString)
  defvalue(QRegex)
  defquote(QNumber, value : BigDecimal)

  defquote(QQuote, quote : Quote)
  defquote(QVector, items : Quotes)

  defquote(QURef)
  defquote(QUPop)

  defquote(QUnary, operator : String, operand : Quote)
  defquote(QBinary, operator : String, left : Quote, right : Quote)
  defquote(QCall, callee : Quote, args : Quotes)

  defquote(QAssign, target : String, value : Quote, global : Bool)
  defquote(QBinaryAssign, operator : String, target : String, value : Quote)

  defquote(QIntoBool, value : Quote)
  defquote(QReturnDecrement, target : String)
  defquote(QReturnIncrement, target : String)

  defquote(QAccessField, head : Quote, tail : FieldAccessors)

  defquote(QMapSpread, operator : Quote, operand : Quote, iterative : Bool)
  defquote(QReduceSpread, operator : String, operand : Quote)

  defquote(QBlock, body : Quotes)
  defquote(QIf, cond : Quote, suc : Quote, alt : Quote?)

  defquote(QFun,
    name : String,
    params : Array(String),
    body : Quotes,
    given : Quotes,
    slurpy : Bool)

  defquote(QEnsure, expression : Quote)
  defquote(QQueue, value : Quote)

  defquote(QInfiniteLoop, repeatee : Quote)
  defquote(QBaseLoop, base : Quote, repeatee : Quote)
  defquote(QStepLoop, base : Quote, step : Quote, repeatee : Quote)
  defquote(QComplexLoop,
    start : Quote,
    base : Quote,
    step : Quote,
    repeatee : Quote)

  defquote(QExpose, pieces : Array(String))
  defquote(QDistinct, pieces : Array(String))

  defquote(QNext, scope : String?, args : Quotes)
  defquote(QReturnStatement, value : Quote)
  defquote(QReturnExpression, value : Quote)

  defquote(QBox,
    name : String,
    params : Array(String),
    given : Quotes,
    namespace : Hash(String, Quote))
end
