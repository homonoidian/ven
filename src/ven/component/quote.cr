module Ven::Component
  # The location (*file*name and *line* number) of a `Quote`.
  struct QTag
    getter file, line

    def initialize(
      @file : String,
      @line : UInt32)
    end
  end

  # The base class of all Ven AST nodes, which are called *quotes*
  # in Ven.
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

        def to_s(io)
          io << "(" << {{@type.name}}

          \{% for field in fields %}
            io << " " << \{{field}}
          \{% end %}

          io << ")"
        end
      end
    end
  end

  # :nodoc:
  alias Quotes = Array(Quote)

  # Define a *quote* with *fields*. *fields* are `TypeDeclaration`s.
  private macro defquote(quote, *fields)
    class {{quote}} < Quote
      defquote!({{*fields}})
    end
  end

  # Pass `defquote` a *quote* and a field `value : String`.
  private macro defvalue(quote)
    defquote({{quote}}, value : String)
  end

  defvalue(QSymbol)
  defvalue(QString)
  defvalue(QNumber)
  defvalue(QRegex)
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

  defquote(QWhile, condition : Quote, body : Quote)
  defquote(QUntil, condition : Quote, body : Quote)
end
