require "big/json"

module Ven::Suite
  # The location (*file*name and *line*number) of a `Quote`.
  struct QTag
    include JSON::Serializable

    getter file : String
    getter line : Int32

    def initialize(@file, @line)
    end

    # Returns a void tag.
    def self.void
      new("<void>", 1)
    end

    # Returns whether this tag is equal to the *other* tag.
    def ==(other : QTag)
      @file == other.file && @line == other.line
    end

    def clone
      self
    end
  end

  # The base class of all Ven AST nodes, which are called
  # **quotes** in Ven.
  #
  # Supports JSON serialization & deserialization.
  abstract class Quote
    include JSON::Serializable

    macro finished
      # This (supposedly) makes it possible to reconstruct
      # a Quote tree from JSON. Will probably be useful in
      # the future, i.e., when debugging?
      use_json_discriminator("__quote", {
        {% for subclass in @type.all_subclasses %}
          {{subclass.name.split("::").last}} => {{subclass}},
        {% end %}
      })
    end

    macro inherited
      # Internal (although not so much) instance variable that
      # stores the typename of this quote (QRuntimeSymbol, QBox,
      # QFun, etc.) It is used to determine the type of Quote
      # to deserialize to.
      @__quote = {{@type.name.split("::").last}}

      macro defquote!(*fields)
        getter tag : QTag
        property \{{*fields.map(&.var.id)}}

        def initialize(@tag,
          \{% for field in fields %}
            @\{{field}},
          \{% end %})
        end

        # Lisp-like pretty-printing.
        #
        # This is more of an internal way to print Quotes. If
        # you want to see Quotes as Ven code, use `Detree`.
        def to_s(io)
          io << "(" << {{@type.name.split("::").last}}

          \{% for field in fields %}
            %field = \{{field.var}}
            %field.is_a?(Array) \
              ? io << " " << "[" << %field.join(" ") << "]"
              : io << " " << %field
          \{% end %}

          io << ")"
        end
      end

      def_clone
    end
  end

  # :nodoc:
  alias Quotes = Array(Quote)

  # Defines a *quote* with *fields*, which are `TypeDeclaration`s.
  private macro defquote(quote, *fields, under parent = Quote)
    class {{quote}} < {{parent}}
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

  # The parent of all kinds of Ven symbols.
  #
  # It is serializable; it is possible to have QSymbol be a
  # key in a JSON object.
  class QSymbol < Quote
    include JSON::Serializable

    # QSymbols should always be resolved to either QRuntimeSymbol
    # or QReadtimeSymbol, orelse a lot of stuff will break. This
    # should not have been required, as __quote is already present
    # on each Quote; but it is!
    use_json_discriminator("__quote", {
      "QRuntimeSymbol"  => QRuntimeSymbol,
      "QReadtimeSymbol" => QReadtimeSymbol,
    })

    getter tag : QTag
    getter value : String

    def to_s(io)
      io << @value
    end

    # Returns the value of this symbol. Thanks to this, QSymbols
    # can be used as keys in a JSON object.
    def to_json_object_key
      value
    end

    # Makes a QRuntimeSymbol from the given JSON object *key*.
    def self.from_json_object_key?(key)
      QRuntimeSymbol.new(QTag.void, key)
    end
  end

  defquote(QRuntimeSymbol, value : _, under: QSymbol)
  defquote(QReadtimeSymbol, value : _, under: QSymbol)

  defvalue(QString)
  defvalue(QRegex)
  defquote(QNumber, value : BigDecimal)

  defquote(QQuote, quote : Quote)
  defquote(QVector, items : Quotes, filter : Quote?)

  defquote(QURef)
  defquote(QUPop)

  defquote(QUnary, operator : String, operand : Quote)
  defquote(QBinary, operator : String, left : Quote, right : Quote)
  defquote(QCall, callee : Quote, args : Quotes)

  defquote(QAssign, target : Quote, value : Quote, global : Bool)
  defquote(QBinaryAssign, operator : String, target : Quote, value : Quote)

  defquote(QDies, operand : Quote)
  defquote(QIntoBool, operand : Quote)
  defquote(QReturnDecrement, target : QSymbol)
  defquote(QReturnIncrement, target : QSymbol)

  defquote(QAccess, head : Quote, args : Quotes)
  defquote(QAccessField, head : Quote, tail : FieldAccessors)

  defquote(QMapSpread, operator : Quote, operand : Quote, iterative : Bool)
  defquote(QReduceSpread, operator : String, operand : Quote)

  defquote(QBlock, body : Quotes)
  defquote(QGroup, body : Quotes)

  defquote(QIf, cond : Quote, suc : Quote, alt : Quote?)

  defquote(QFun,
    name : QSymbol,
    params : Parameters,
    body : Quotes,
    blocky : Bool)

  defquote(QQueue, value : Quote)

  defquote(QInfiniteLoop, repeatee : Quote)
  defquote(QBaseLoop, base : Quote, repeatee : Quote)
  defquote(QStepLoop, base : Quote, step : Quote, repeatee : Quote)
  defquote(QComplexLoop,
    start : Quote,
    base : Quote,
    step : Quote,
    repeatee : Quote)

  defquote(QNext, scope : String?, args : Quotes)
  defquote(QReturnQueue)
  defquote(QReturnStatement, value : Quote)
  defquote(QReturnExpression, value : Quote)

  defquote(QBox,
    name : QSymbol,
    params : Parameters,
    namespace : Hash(QSymbol, Quote))

  defquote(QLambda,
    params : Array(String),
    body : Quote,
    slurpy : Bool)

  defquote(QEnsure, expression : Quote)
  defquote(QEnsureTest, comment : Quote, shoulds : Quotes)
  defquote(QEnsureShould, section : String, pad : Quotes)

  defquote(QPatternShell, pattern : Quote)

  defquote(QImmediateBox, box : QBox)
end
