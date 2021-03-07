module Ven::Suite
  # The location (*file*name and *line* number) of a `Quote`.
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

  # A thin compatibility layer between the `Reader` and the
  # `Machine`.
  class QModelCarrier < QVoid
    getter model

    def initialize(@model : Model)
      super()
    end

    def to_s(io)
      io << "<carrier for " << @model << ">"
    end
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

  defquote(QAssign, target : String, value : Quote, local : Bool)
  defquote(QBinaryAssign, operator : String, target : String, value : Quote)

  defquote(QIntoBool, value : Quote)
  defquote(QReturnDecrement, target : String)
  defquote(QReturnIncrement, target : String)

  # Part of the field access' (`QAccessField`) path.
  abstract struct FieldAccessor(T)
    getter field

    def initialize(
      @field : T)
    end
  end

  # E.g.: a.b.c
  struct SingleFieldAccessor < FieldAccessor(String)
    def to_s(io)
      io << @field
    end
  end

  # E.g.: a.("b").(foo-bar-baz ~ "2")
  struct DynamicFieldAccessor < FieldAccessor(Quote)
    def to_s(io)
      io << "(<...>)"
    end
  end

  # E.g.: a.["b", "c"]
  struct MultiFieldAccessor < FieldAccessor(Array(DynamicFieldAccessor))
    def to_s(io)
      io << "[<...>]"
    end
  end

  defquote(QAccessField,
    head : Quote,
    path : Array(
      # Crystal doesn't yet support just `FieldAccessor` here,
      # have to write by hand:
      SingleFieldAccessor  |
      DynamicFieldAccessor |
      MultiFieldAccessor))

  defquote(QBinarySpread, operator : String, operand : Quote)
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
