module Ven::Component
  # The location (*file*name and *line* number) of a `Quote`.
  struct QTag
    getter file, line

    def initialize(
      @file : String,
      @line : UInt32)
    end
  end

  # The base class of all Ven AST nodes, which are called
  # **quotes** in Ven. It is also a type accessible from Ven.
  abstract class Quote < MClass
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
              field = \{{field.var}}

              field.is_a?(Array) \
                ? io << " " << "[" << field.join(" ") << "]"
                : io << " " << field
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

  defvalue(QSymbol)
  defvalue(QString)
  defvalue(QNumber)
  defvalue(QRegex)

  defquote(QQuote, quote : Quote)
  defquote(QVector, items : Quotes)

  defquote(QURef)
  defquote(QUPop)

  defquote(QUnary, operator : String, operand : Quote)
  defquote(QBinary, operator : String, left : Quote, right : Quote)
  defquote(QCall, callee : Quote, args : Quotes)

  defquote(QAssign, target : String, value : Quote)
  defquote(QBinaryAssign, operator : String, target : String, value : Quote)

  defquote(QIntoBool, value : Quote)
  defquote(QReturnDecrement, target : String)
  defquote(QReturnIncrement, target : String)

  defquote(QAccessField, head : Quote, path : Array(String))

  defquote(QBinarySpread, operator : String, body : Quote)
  defquote(QLambdaSpread, lambda : Quote, operand : Quote, iterative : Bool)

  defquote(QBlock, body : Quotes)
  defquote(QIf, cond : Quote, suc : Quote, alt : Quote?)

  defquote(QFun,
    name :  String,
    params : Array(String),
    body : Quotes,
    given : Quotes,
    slurpy : Bool)

  defquote(QEnsure, expression : Quote)
  defquote(QQueue, value : Quote)

  defquote(QInfiniteLoop, body : Quotes)
  defquote(QBaseLoop, base : Quote, body : Quotes)
  defquote(QStepLoop, base : Quote, step : Quote, body : Quotes)
  defquote(QComplexLoop,
    start : Quote,
    base : Quote,
    pres : Quotes,
    step : Quote,
    body : Quotes)
end
