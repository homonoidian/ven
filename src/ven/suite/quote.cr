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

  # :nodoc:
  alias MaybeQuote = Quote?

  # Defines a *quote* with *fields*, which are `TypeDeclaration`s.
  private macro defquote(quote, *fields, desc = "something", under parent = Quote)
    class {{quote}} < {{parent}}
      defquote!({{*fields}})

      def self.to_s(io)
        io << "quote of " << {{desc}}
      end
    end
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

    def self.to_s(io)
      io << "quote of nothing"
    end
  end

  defquote(QQuoteEnvelope, quote : Quote, desc: "quote envelope")

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

    def self.to_s(io)
      io << "quote of generic symbol"
    end
  end

  defquote(QRuntimeSymbol,
    value : _,
    under: QSymbol,
    desc: "runtime symbol")

  defquote(QReadtimeSymbol,
    value : _,
    under: QSymbol,
    desc: "readtime symbol")

  defquote(QString, value : String, desc: "string")
  defquote(QRegex, value : String, desc: "regex")
  defquote(QNumber, value : BigDecimal, desc: "number")

  defquote(QVector, items : Quotes, filter : MaybeQuote, desc: "vector")

  defquote(QTrue, desc: "bool true")
  defquote(QFalse, desc: "bool false")

  defquote(QURef, desc: "'_'")
  defquote(QUPop, desc: "'&_'")

  defquote(QUnary,
    operator : String,
    operand : Quote,
    desc: "unary operation")

  defquote(QBinary,
    operator : String,
    left : Quote,
    right : Quote,
    desc: "binary operation")

  defquote(QCall, callee : Quote, args : Quotes, desc: "call")

  defquote(QAssign,
    target : Quote,
    value : Quote,
    global : Bool,
    desc: "assignment")

  defquote(QBinaryAssign,
    operator : String,
    target : Quote,
    value : Quote,
    desc: "binary assignment")

  defquote(QDies, operand : Quote, desc: "postifx dies")
  defquote(QIntoBool, operand : Quote, desc: "postfix into-bool")
  defquote(QReturnDecrement, target : QSymbol, desc: "return-decrement")
  defquote(QReturnIncrement, target : QSymbol, desc: "return-increment")

  defquote(QAccess, head : Quote, args : Quotes, desc: "access")
  defquote(QAccessField, head : Quote, tail : FieldAccessors, desc: "field access")

  defquote(QMapSpread,
    operator : Quote,
    operand : Quote,
    iterative : Bool,
    desc: "map spread")

  defquote(QReduceSpread,
    operator : String,
    operand : Quote,
    desc: "reduce spread")

  defquote(QBlock, body : Quotes, desc: "block")
  defquote(QGroup, body : Quotes, desc: "group")

  defquote(QIf, cond : Quote, suc : Quote, alt : MaybeQuote, desc: "if-else")

  defquote(QFun,
    name : QSymbol,
    params : Parameters,
    body : Quotes,
    blocky : Bool,
    desc: "fun definition")

  defquote(QQueue, value : Quote, desc: "queue")

  defquote(QInfiniteLoop,
    repeatee : Quote,
    desc: "infinite loop")

  defquote(QBaseLoop,
    base : Quote,
    repeatee : Quote,
    desc: "base loop")

  defquote(QStepLoop,
    base : Quote,
    step : Quote,
    repeatee : Quote,
    desc: "step loop")

  defquote(QComplexLoop,
    start : Quote,
    base : Quote,
    step : Quote,
    repeatee : Quote,
    desc: "complex (full) loop")

  defquote(QNext, scope : String?, args : Quotes, desc: "next")

  defquote(QReturnQueue, desc: "return queue statement")
  defquote(QReturnStatement, value : Quote, desc: "return statement")
  defquote(QReturnExpression, value : Quote, desc: "return expression")

  defquote(QBox,
    name : QSymbol,
    params : Parameters,
    namespace : Hash(QSymbol, Quote),
    desc: "box definition")

  defquote(QLambda,
    params : Array(String),
    body : Quote,
    slurpy : Bool,
    desc: "lambda definition")

  defquote(QEnsure,
    expression : Quote,
    desc: "ensure expression")

  defquote(QEnsureTest,
    comment : Quote,
    shoulds : Quotes,
    desc: "ensure test")

  defquote(QEnsureShould,
    section : String,
    pad : Quotes,
    desc: "enshure 'should' case")

  defquote(QPatternEnvelope, pattern : Quote, desc: "pattern")
  defquote(QReadtimeEnvelope, expression : Quote, desc: "readtime envelope")

  defquote(QHole, value : MaybeQuote = nil, desc: "readtime hole")

  defquote(QImmediateBox, box : QBox, desc: "immediate box")
end
