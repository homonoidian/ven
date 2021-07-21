require "./*"

module Ven::Suite
  class ReadExpansion < Transformer
    private alias Definitions = Hash(String, Quote)

    # The exception that, if raised inside an envelope, will
    # cause an immediate return with the given *quote*. This
    # means that the envelope will only expand into *quote*.
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
      # The references stack (TODO: redef sema!).
      property refs = Quotes.new

      def initialize(@definitions)
      end

      # Returns a new `Env`, with its `definitions` being a
      # `Hash#merge` of this Env's definitions and *defs*, and
      # all other properties being the same as in this Env.
      def with(defs : Definitions)
        env = Env.new(defs)
        env.queue = @queue
        env.return = @return
        env
      end

      # Returns a new `Env`, with its `refs` being an array
      # of this Env's refs plus *refs*, and all other properties
      # being the same as in this Env.
      def with(refs us : Quotes)
        env = Env.new(@definitions)
        env.refs = @refs + us
        env.queue = @queue
        env.return = @return
        env
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
      QNumber.new(q.tag, ({{value}}).to_big_d)
    end

    # Makes a `QString`.
    #
    # Assumes it's run inside `eval`, with *q* in scope and
    # of type `Quote`. Will crash otherwise.
    private macro str(from value)
      QString.new(q.tag, ({{value}}).to_s)
    end

    # Makes a `QVector`.
    #
    # Assumes it's run inside `eval`, with *q* in scope and
    # of type `Quote`. Will crash otherwise.
    private macro vec(items)
      QVector.new(q.tag, {{items}}, nil)
    end

    # Makes QTrue or QFalse, depending on whether *value* is
    # true (actually, anything but false) or false.
    private macro bool(value)
      ({{value}}) == false ? QFalse.new(q.tag) : QTrue.new(q.tag)
    end

    # Uses `unary` *operator* to convert *operand* to *type*.
    private macro unary_to(operator, operand, cast type)
      %operand = {{operand}}

      unary({{operator}}, %operand).as?({{type}}) ||
        die("could not cast #{%operand.class} to #{{{type}}}")
    end

    # Implements Ven unary operator semantics.
    def unary(operator : String, operand : Quote)
      q = operand

      case operator
      when "+"
        case operand
        when QNumber then operand
        when QString then num operand.value
        when QVector then num operand.items.size
        when QTrue   then num 1
        when QFalse  then num 0
        end
      when "-"
        case operand
        when QVector then num -operand.items.size
        when QString then num "-#{operand.value}"
        when QNumber then num -operand.value
        when QTrue   then num -1
        when QFalse  then num 0
        end
      when "~"
        case operand
        when QString then operand
        when QNumber then str operand.value
        else
          str Detree.detree(operand)
        end
      when "#"
        case operand
        when QString then num operand.value.size
        when QVector then num operand.items.size
        else
          num Detree.detree(operand).size
        end
      when "&"
        operand.as?(QVector) || vec [operand]
      when "not"
        bool operand.is_a?(QFalse)
      end
    end

    # Implements Ven binary operator semantics.
    def binary(operator : String, left : Quote, right : Quote)
      q = left

      # The o_ prefix in o_left, o_right means **operant**,
      # i.e., that on which something (the operator in our
      # case) operates.
      case operator
      when "and" then left.as?(QFalse) || right
      when "or"  then left.is_a?(QFalse) ? right : left
      when "is"  then is?(left, right)
      when "in"
        if left.is_a?(QString) && right.is_a?(QString)
          # If both sides are strings, do a substring search.
          right.value.includes?(left.value) ? left : bool false
        elsif right.is_a?(QVector)
          # If the right side is a vector, go through its items,
          # trying to find *left* (whatever it is). Return the
          # **found** value.
          right.items.each do |item|
            return item unless is?(item, left).is_a?(QFalse)
          end
        end

        bool false
      when "<", ">", "<=", ">="
        if left.is_a?(QString) && right.is_a?(QString)
          o_left = left.value.size
          o_right = right.value.size
        else
          o_left = unary_to("+", left, QNumber).value
          o_right = unary_to("+", right, QNumber).value
        end

        case operator
        when "<"  then bool o_left < o_right
        when ">"  then bool o_left > o_right
        when "<=" then bool o_left <= o_right
        when ">=" then bool o_left >= o_right
        end
      when "+", "-", "*", "/"
        o_left = unary_to("+", left, QNumber).value
        o_right = unary_to("+", right, QNumber).value

        case operator
        when "+" then num o_left + o_right
        when "-" then num o_left - o_right
        when "*" then num o_left * o_right
        when "/" then num o_left / o_right
        end
      when "&"
        o_left = unary_to("&", left, QVector).items
        o_right = unary_to("&", right, QVector).items
        vec o_left + o_right
      when "~"
        o_left = unary_to("~", left, QString).value
        o_right = unary_to("~", right, QString).value
        str o_left + o_right
      when "x"
        # Normalize the sides, similar to `Machine#normalize?`.
        o_left, o_right =
          case {left, right}
          when {_, QVector}, {_, QString}
            # `n x "hello"`   ==> `"hello" x +n`
            # `n x [2, 3, 4]` ==> `[2, 3, 4] x +n`
            {right, unary_to("+", left, QNumber)}
          when {QString, _}, {QVector, _}
            # `"hello" x n` ==> `"hello" x +n`
            # `[2, 3, 4] x n` ==> `[2, 3, 4] x +n`
            {left, unary_to("+", right, QNumber)}
          else
            # `foo x n` ==> `&foo x +n`
            {unary_to("&", left, QVector),
             unary_to("+", right, QNumber)}
          end

        amount = o_right.value.to_big_i

        # Save from overflow. Although Int32::MAX is a big number
        # and it's dangerous to make such a long vector, it's still
        # safer than a limitless BigDecimal.
        if amount > Int32::MAX
          die("'x': amount overflew")
        end

        if o_left.is_a?(QVector)
          vec o_left.items * amount
        elsif o_left.is_a?(QString)
          str o_left.value * amount
        end
      end
    end

    # Implements runtime Ven 'is' semantics, and readtime
    # Ven 'is' semantics.
    #
    # Readtime Ven semantics kicks in when *left*, or *right*,
    # or both of them are quotes other than `QNumber`, `QString`,
    # `QVector`, `QTrue`/`QFalse`, and a few others (refer to
    # the source code). In this case, it recursively compares
    # the fields of the two quotes.
    def is?(left : Quote, right : Quote)
      q = left

      # If the classes aren't equal, the content doesn't even
      # matter. Return false right away.
      return bool false unless left.class == right.class

      case left
      when QNumber
        return bool false unless left.value == right.as(QNumber).value
      when QString
        return bool false unless left.value == right.as(QString).value
      when QVector
        lefts = left.items
        rights = right.as(QVector).items

        # If sizes of the two vectors are not equal, the
        # vectors themselves are not equal.
        return bool false if lefts.size != rights.size

        # Compare the items with each other, and, if one is
        # not equal to the other, the vectors themselves are
        # not equal.
        lefts.each_with_index do |item, index|
          return bool false if is?(item, rights[index]).is_a?(QFalse)
        end
      when QTrue, QFalse
        # Cannot return *left*, because, say, `false is false`
        # will return `false`, and that's just wrong.
        return bool true
      else
        # We're taking the short path here,
        return bool false unless left.to_json == right.to_json
      end

      left
    end

    # Calls `eval(env, quote)` for every quote of *quotes*.
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
      when QNumber, QString, QRegex, QTrue, QFalse
        # Homoiconic quotes are the bread-and-butter of readtime
        # Ven. They are the values of readtime Ven.
        quote
      else
        # We use ReadError here, as 'die' can't take custom tag.
        raise ReadError.new(quote.tag,
          "#{quote.class} not supported in readtime envelope")
      end
    end

    def eval(env, q : QVector)
      vec eval(env, q.items)
    end

    def eval(env, q : QSuperlocalTake)
      env.refs.pop? || die("TODO redef sema '_': no referent")
    end

    def eval(env, q : QSuperlocalTap)
      env.refs.last? || die("TODO redef sema '&_': no referent")
    end

    def eval(env, q : QReadtimeSymbol)
      die("there is no need to emphasize readtime symbols " \
          "in a readtime envelope: it's readtime anyway")
    end

    def eval(env, q : QRuntimeSymbol)
      env.definitions[q.value]? || die("readtime symbol not found: #{q.value}")
    end

    def eval(env, q : QUnary)
      operand = eval(env, q.operand)

      unary(q.operator, operand) ||
        die("'#{q.operator}' does not support #{operand.class}")
    end

    def eval(env, q : QBinary)
      left = eval(env, q.left)

      # Short-circuiting for 'and' and 'or'. Although they
      # have very similar implementations, I still cannot
      # merge them into one.
      if q.operator == "and"
        return left if left.is_a?(QFalse)
        return eval(env, q.right)
      elsif q.operator == "or"
        return left unless left.is_a?(QFalse)
        return eval(env, q.right)
      end

      right = eval(env, q.right)

      binary(q.operator, left, right) ||
        die("'#{q.operator}' does not support #{left.class}, #{right.class}")
    end

    def eval(env, q : QCall)
      unless callee = q.callee.as?(QSymbol)
        die("illegal callee: #{callee.class}")
      end

      # `quote()`s are an exception to the rule of evaluating
      # the arguments.
      if callee.value == "quote"
        return QQuoteEnvelope.new(q.tag,
          q.args.first? || die("quote(): improper arguments")
        )
      end

      args = eval(env, q.args)

      # Those below are readtime builtins. They're a bunch of
      # primitive 'functions' that give the user access to
      # the Reader (upon evaluation), I/O (mostly for debugging),
      # type manipulation, quote creation, etc.
      case callee.value
      when "say"
        # Outputs the arguments to the screen. If called with
        # one argument, it returns that argument untouched.
        # If called with multiple arguments, it returns a
        # vector of those arguments.
        args.each do |arg|
          puts unary_to("~", arg, QString).value
        end

        args.size == 1 ? args.first : vec args
      when "chars"
        # TEMPORARY (TODO: `"foo"[]`): returns a vector of
        # characters of the given string.
        die("chars(): improper arguments") unless args.size == 1

        chars = unary_to("~", arg = args.first, QString)
          .value
          .chars
          .map do |char|
            QString.new(arg.tag, char.to_s).as(Quote)
          end

        vec chars
      when "reverse"
        # TEMPORARY (TODO: `"foo"[from -1]` or `"foo"[-1 to 0]`):
        # reverses the given string.
        die("reverse(): improper arguments") unless args.size == 1

        str unary_to("~", args.first, QString).value.reverse
      else
        die("unsupported call quote")
      end
    end

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

    def eval(env, q : QEnsure)
      if (expression = eval(env, q.expression)).is_a?(QFalse)
        # We err using ReadError here, as 'die' can't take
        # custom tag, and we need to point to the cause as
        # precisely as possible.
        raise ReadError.new(q.tag, "ensure: got false")
      else
        expression
      end
    end

    def eval(env, q : QBlock)
      # New definitions in the block will be discarded after
      # it's evaluated, but old are still accessible & mutable.
      eval(env.dup, q.body).last? || die("empty block")
    end

    def eval(env, q : QQueue)
      # You can think of queue values as being **outside** of
      # readtime envelope, but still inside readtime context:
      # `queue a + b` queues `a + b`; `queue $a + $b` queues
      # `queue value-of-a + value-of-b`.
      #
      # If there are unfilled holes, we mutate the first hole's
      # value with this queue's expression.
      #
      # If there are no holes, we append the value to the
      # queue, as expected.
      if !@holes.empty?
        @holes.shift.value = transform(q.value)
      else
        env.queue << transform(q.value)
      end

      q.value
    end

    def eval(env, q : QReturnExpression)
      # QReturnExpression, as in runtime Ven, just sets the
      # return value without interrupting control flow.
      env.return = transform(q.value)

      q.value
    end

    def eval(env, q : QReturnStatement)
      # QReturnStatement, as in runtime Ven, interrupts control
      # flow and returns out of this envelope immediately.
      raise ReturnException.new(transform(q.value))
    end

    def eval(env, q : QMapSpread)
      operand = eval(env, q.operand)

      if !operand.is_a?(QVector) || operand.items.size == 0
        return operand
      elsif operand.items.size < 2
        return operand.items.first
      end

      items = operand.items

      if q.iterative
        # Iterative map spreads do '.each' instead of '.map',
        # and return a copy of the original operand.
        items.each do |item|
          eval(env.with([item]), q.operator.clone)
        end
      else
        items = items.map do |item|
          eval(env.with([item]), q.operator.clone)
        end
      end

      vec items
    end

    def eval(env, q : QReduceSpread)
      operand = eval(env, q.operand)

      case operand
      when QQuoteEnvelope
        # Quote joining mode: `|and| quote([a, b, c])` returns
        # `a and b and c`.
        return operand unless contents = operand.quote.as?(QVector)

        contents.items.reduce do |memo, item|
          QBinary.new(q.tag, q.operator, memo, item)
        end
      when QVector
        # Readtime reduce spread mode: `|+| [1, 2, 3]`
        # returns 6.
        return operand.items.first? || operand if operand.items.size < 2

        operand.items.reduce do |memo, item|
          binary(q.operator, memo, item) ||
            die("|#{q.operator}|: cannot reduce #{memo.class}, #{item.class}")
        end
      else
        operand
      end
    end

    def eval(env, q : QIf)
      if eval(env, q.cond).is_a?(QFalse)
        eval(env, q.alt || return bool false)
      else
        eval(env, q.suc)
      end
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
      q.value || @holes << q
    end

    # Expands to the quote produced by the expression of the
    # readtime envelope.
    deftransform QReadtimeEnvelope do
      env = Env.new(@definitions)

      begin
        body = eval(env, quote.expression)
      rescue e : ReturnException
        # Statement return causes an immediate return.
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
      if !env.queue.empty?
        return QGroup.new(quote.tag, transform(env.queue))
      elsif returned = env.return.as?(Quote)
        return transform(returned)
      end

      transform(body)
    end
  end
end
