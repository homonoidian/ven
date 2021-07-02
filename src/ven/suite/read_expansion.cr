require "./*"

module Ven::Suite
  class ReadExpansion < Transformer
    private alias Definitions = Hash(String, Quote)

    # The exception that, if raised inside an envelope, will
    # cause immediate return with the given *quote*. This means
    # that the envelope will only expand into *quote*.
    private class ReturnException < Exception
      getter quote : Quote

      def initialize(@quote)
      end
    end

    # The environment of a single readtime envelope.
    private class Env
      # The queue of quotes. Queue overrides expression-return
      # & implicit last quote return, and makes the envelope
      # expand into a QGroup of the Quotes.
      property queue = Quotes.new
      # The expression-return value.
      property return : Quote? = nil
      # A hash of readtime symbol definitions.
      property definitions : Definitions

      def initialize(@definitions)
      end
    end

    def initialize(@definitions : Definitions)
      @holes = [] of QHole
    end

    # Makes a `QNumber`.
    #
    # Assumes it's run inside `eval`, with *q* in scope and
    # of type `Quote`. Will crash otherwise.
    private macro num(from value)
      QNumber.new(q.tag, {{value}}.to_big_d)
    end

    # Makes a `QString`.
    #
    # Assumes it's run inside `eval`, with *q* in scope and
    # of type `Quote`. Will crash otherwise.
    private macro str(from value)
      QString.new(q.tag, {{value}}.to_s)
    end

    # Makes a `QVector`.
    #
    # Assumes it's run inside `eval`, with *q* in scope and
    # of type `Quote`. Will crash otherwise.
    private macro vec(items)
      QVector.new(q.tag, {{items}}, nil)
    end

    # Calls `eval(env, quotes)` for every quote of *quotes*.
    def eval(env, quotes : Quotes)
      quotes.map do |quote|
        eval(env, quote)
      end
    end

    # Implements Ven readtime semantics for the given quote,
    # taking into account the environment, *env*.
    #
    # Readtime semantics is an alternative interpretation of
    # quotes. Some may say, an alternative backend to quotes.
    # Some quotes are homoiconic (they represent themselves),
    # and some aren't. Those homoiconic quotes are values for
    # readtime Ven, in the same sense Models are for runtime
    # Ven.
    #
    # Returns the resulting quote.
    def eval(env, quote : Quote)
      case quote
      when QNumber, QString, QRegex, QTrue, QFalse, QHole
        # Homoiconic quotes are the bread-and-butter of readtime
        # Ven. They are the values of readtime Ven.
        quote
      else
        # We use ReadError here, as 'die' can't take custom tag.
        raise ReadError.new(quote.tag, "#{quote.class} not supported in readtime envelope")
      end
    end

    # :ditto:
    def eval(env, q : QVector)
      vec eval(env, q.items)
    end

    # :ditto:
    def eval(env, q : QReadtimeSymbol)
      die("there is no need to emphasize readtime symbols " \
          "in a readtime envelope: it's readtime anyway")
    end

    # :ditto:
    def eval(env, q : QRuntimeSymbol)
      env.definitions[q.value]? || die("readtime symbol not found: #{q.value}")
    end

    # :ditto:
    def eval(env, q : QUnary)
      operand = eval(env, q.operand)

      case q.operator
      when "+"
        case operand
        when QNumber
          return operand
        when QString
          return num operand.value
        when QVector
          return num operand.items.size
        end
      when "-"
        case operand
        when QVector
          return num -operand.items.size
        when QNumber, QString
          return num -operand.value
        end
      when "~"
        case operand
        when QString
          return operand
        when QNumber
          return str operand.value
        else
          return str Detree.detree(operand)
        end
      when "#"
        case operand
        when QString
          return num operand.value.size
        when QVector
          return num operand.items.size
        else
          return num Detree.detree(operand).size
        end
      when "&"
        case operand
        when QVector
          return operand
        else
          return vec [operand]
        end
      when "not"
        case operand
        when QFalse
          return QTrue.new(q.tag)
        end
      end

      die("operation not supported: '#{q.operator}', #{operand.class}")
    end

    # :ditto:
    def eval(env, q : QAssign)
      unless target = q.target.as?(QRuntimeSymbol)
        die("unsupported assignment target: #{target.class}")
      end

      # Note how we don't take global assignment (:=) into
      # account. Well, there is no point in doing that: `:=`
      # works on scope stack, and there's no scope stack at
      # read-time.
      env.definitions[target.value] = eval(env, q.value)
    end

    # :ditto:
    def eval(env, q : QEnsure)
      operand = eval(env, q.expression)
      operand.is_a?(QFalse) ? die("ensure: got false") : operand
    end

    # :ditto:
    def eval(env, q : QBlock)
      # New definitions in the block will be discarded after
      # it's evaluated, but old are still accessible & mutable.
      eval(env.dup, q.body)
      # Currently, returning QVoid seems the most correct
      # choice. Probably will rethink later.
      QVoid.new
    end

    # :ditto:
    def eval(env, q : QQueue)
      # You can think of queue values as being **outside**
      # of readtime envelope, but still inside the readtime
      # context.
      #
      # If there are holes, we shift-fill them with the
      # value of this queue.
      #
      # If there are no holes, we append the value to
      # the queue.
      if !@holes.empty?
        @holes.shift.value = transform(q.value)
      else
        env.queue << transform(q.value)
      end

      q.value
    end

    # :ditto:
    def eval(env, q : QReturnExpression)
      # QReturnExpression, as with runtime Ven, just sets
      # the return value without interrupting control flow.
      env.return = transform(q.value)

      q.value
    end

    # :ditto:
    def eval(env, q : QReturnStatement)
      # QReturnStatement, as with runtime Ven, interrupts control
      # flow and returns out of this envelope immediately.
      raise ReturnException.new(transform(q.value))
    end

    # Expands to the quote the symbol was assigned.
    def transform!(q : QReadtimeSymbol)
      @definitions[q.value]? ||
        die("there is no readtime symbol named '$#{q.value}'")
    end

    # Adds the hole to the holes of this ReadExpansion.
    #
    # Alternatively, if the hole has a value, expands to
    # that value.
    def transform!(q : QHole)
      # We have to manually transform() here, as Transformer
      # does not recognize Quote? as valid transformable
      # property, and it's quite hard to convince it that
      # it is.
      transform(q.value) || @holes << q
    end

    # Expands to the quote produced by the expression of the
    # readtime envelope.
    deftransform QReadtimeEnvelope do
      env = Env.new(@definitions)

      begin
        body = eval(env, quote.expression)
      rescue e : ReturnException
        return transform(e.quote)
      ensure
        if @holes.size == 1
          die("there is 1 unfilled queue hole")
        elsif @holes.size > 1
          die("there are #{@holes.size} unfilled queue holes")
        end
      end

      # Implicit return policy is the same as in runtime Ven:
      # queue overrides expression-return quote, expression-
      # return quote overrides implicit last quote return.
      #
      # Statement return causes an immediate return via the
      # ReturnException, and so is not handled here.
      if !env.queue.empty?
        return QGroup.new(quote.tag, transform(env.queue))
      elsif returned = env.return.as?(Quote)
        return transform(returned)
      end

      transform(body)
    end
  end
end
