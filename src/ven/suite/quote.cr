require "big/json"

module Ven::Suite::QuoteSuite
  # Pretty self-explanatory: an array of quotes.
  alias Quotes = Array(Quote)

  # Although this alias may seem redundant, `MaybeQuote` is
  # detectable by `Suite::Transformer` (contrary to `Quote?`),
  # and is useful because of that.
  alias MaybeQuote = Quote?

  # The location (*file*name and *line*number) of a `Quote`.
  struct QTag
    include JSON::Serializable

    # Returns the begin column of this quote. Currently, it
    # is set to the begin column of the word that initiated
    # this quote.
    getter begin_column : Int32?
    # Returns the end column of this quote. Currently, it is
    # set to the end column of the word that initiated this
    # quote.
    getter end_column : Int32?

    # Returns the name of the file this quote was read from.
    getter file : String
    # Returns the line number of the beginning of this quote.
    getter line : Int32

    def initialize(@file, @line, @begin_column = nil, @end_column = nil)
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

      # Returns whether this quote is a `QFalse`.
      def false?
        {{@type.resolve.id.ends_with?("QFalse")}}
      end

      # Free to interpret by quotes, but generally tells
      # whether a quote is expected to be in a statement
      # position.
      def stmtish?
        false
      end

      macro defquote!(*fields)
        # Returns the location of this quote. See `QTag`.
        getter tag : QTag

        property \{{*fields.map(&.var.id)}}

        def initialize(@tag,
          \{% for field in fields %}
            @\{{field}},
          \{% end %})
          # If @field is a `Quote`, we probably don't want it
          # to be a `QGroup`. QGroups are for `Quotes`, not
          # `Quote`. Many things will break otherwise. Same in
          # `Parameter`, `FieldAccessor`, which are wrappers
          # around `Quote`.
          \{% for field in fields %}
            \{% if field.type.resolve == Quote %}
              if @\{{field.var}}.is_a?(QGroup)
                raise ReadError.new(@tag, "got group where expression expected")
              end
            \{% end %}
          \{% end %}
        end

        # Internal, fallback quote pretty-printing. Consider
        # using `Detree` instead.
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

  # Defines a *quote* with *fields*, which are `TypeDeclaration`s.
  private macro defquote(quote, *fields, desc = "something", under parent = Quote, stmtish = false)
    class {{quote}} < {{parent}}
      defquote!({{*fields}})

      # See `Quote#stmtish?`.
      def stmtish?
        {{stmtish}}
      end

      def self.to_s(io)
        io << "quote of " << {{desc}}
      end
    end
  end

  defquote(QQuoteEnvelope, quote : Quote, desc: "quote envelope")

  defquote(QRuntimeSymbol,
    value : String,
    under: QSymbol,
    desc: "runtime symbol",
  )

  defquote(QReadtimeSymbol,
    value : String,
    under: QSymbol,
    desc: "readtime symbol",
  )

  defquote(QString, value : String, desc: "string")
  defquote(QRegex, value : String, desc: "regex")
  defquote(QNumber, value : BigDecimal, desc: "number")

  defquote(QVector, items : Quotes, desc: "vector")
  defquote(QFilterOver,
    subject : Quote,
    filter : Quote,
    desc: "filtered vector",
  )

  defquote(QMap, keys : Quotes, vals : Quotes, desc: "map")

  defquote(QTrue, desc: "bool true")
  defquote(QFalse, desc: "bool false")

  defquote(QSuperlocalTake, desc: "superlocal take")
  defquote(QSuperlocalTap, desc: "superlocal tap")

  defquote(QUnary,
    operator : String,
    operand : Quote,
    desc: "unary operation",
  )

  defquote(QBinary,
    operator : String,
    left : Quote,
    right : Quote,
    desc: "binary operation",
  )

  defquote(QCall, callee : Quote, args : Quotes, desc: "call")

  defquote(QAssign,
    target : Quote,
    value : Quote,
    global : Bool,
    desc: "assignment",
  )

  defquote(QBinaryAssign,
    operator : String,
    target : Quote,
    value : Quote,
    desc: "binary assignment",
  )

  defquote(QDies, operand : Quote, desc: "postfix dies")
  defquote(QIntoBool, operand : Quote, desc: "postfix into-bool")
  defquote(QReturnDecrement, target : QSymbol, desc: "return-decrement")
  defquote(QReturnIncrement, target : QSymbol, desc: "return-increment")

  defquote(QAccess, head : Quote, args : Quotes, desc: "access")
  defquote(QAccessField,
    head : Quote,
    tail : FieldAccessors,
    desc: "field access",
  )

  defquote(QMapSpread,
    operator : Quote,
    operand : Quote,
    iterative : Bool,
    desc: "map spread",
  )

  defquote(QReduceSpread,
    operator : String,
    operand : Quote,
    desc: "reduce spread",
  )

  defquote(QBlock, body : Quotes, desc: "block")
  defquote(QGroup, body : Quotes, desc: "group")

  defquote(QIf,
    cond : Quote,
    suc : Quote,
    alt : MaybeQuote,
    desc: "if-else",
  )

  defquote(QFun,
    name : QSymbol,
    params : Parameters,
    body : Quotes,
    blocky : Bool,
    desc: "fun definition",
    stmtish: true,
  )

  defquote(QQueue, value : Quote, desc: "queue")

  defquote(QInfiniteLoop,
    repeatee : Quote,
    desc: "infinite loop",
    stmtish: true,
  )

  defquote(QBaseLoop,
    base : Quote,
    repeatee : Quote,
    desc: "base loop",
    stmtish: true,
  )

  defquote(QStepLoop,
    base : Quote,
    step : Quote,
    repeatee : Quote,
    desc: "step loop",
    stmtish: true,
  )

  defquote(QComplexLoop,
    start : Quote,
    base : Quote,
    step : Quote,
    repeatee : Quote,
    desc: "complex (full) loop",
    stmtish: true,
  )

  defquote(QNext, scope : String?, args : Quotes, desc: "next")

  defquote(QReturnQueue, desc: "return queue statement")
  defquote(QReturnStatement,
    value : Quote,
    desc: "return statement",
    stmtish: true,
  )
  defquote(QReturnExpression,
    value : Quote,
    desc: "return expression",
  )

  defquote(QBox,
    name : QSymbol,
    params : Parameters,
    namespace : Hash(QSymbol, Quote),
    desc: "box definition",
    stmtish: true,
  )

  defquote(QLambda,
    params : Array(String),
    body : Quote,
    slurpy : Bool,
    desc: "lambda definition",
  )

  defquote(QEnsure,
    expression : Quote,
    desc: "ensure expression",
  )

  defquote(QEnsureTest,
    comment : Quote,
    shoulds : Quotes,
    desc: "ensure test",
    stmtish: true,
  )

  defquote(QEnsureShould,
    section : String,
    pad : Quotes,
    desc: "ensure 'should' case",
  )

  defquote(QPatternEnvelope, pattern : Quote, desc: "pattern")
  defquote(QReadtimeEnvelope, expression : Quote, desc: "readtime envelope")

  defquote(QHole, value : MaybeQuote = nil, desc: "readtime hole")

  defquote(QImmediateBox,
    box : QBox,
    desc: "immediate box",
    stmtish: true,
  )
end

module Ven::Suite
  include QuoteSuite
end
