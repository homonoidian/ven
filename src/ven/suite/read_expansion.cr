require "./**"

module Ven::Suite
  # Readtime semantics is an alternative interpretation of
  # quotes. Some may say, an alternative backend to quotes.
  #
  # A few quotes are homoiconic, and are the values of readtime
  # Ven: `QNumber`, `QString`, `QVector`, to name a few.
  #
  # The other quotes are either interpreted, or cause a death
  # when met.
  class ReadExpansion < Transformer
    include Readtime::Unary
    include Readtime::Binary

    # The exception that, if raised inside an envelope, will
    # cause an immediate return with the given *quote*. This
    # means that the envelope will only expand into *quote*.
    private class ReturnException < Exception
      getter quote : Quote

      def initialize(@quote)
      end
    end

    # The maximum amount of characters in the representation
    # string (see `repr`).
    REPR_CAP = 32

    def initialize(
      @parent : Parselet::Parselet,
      @reader : Reader,
      @definitions : Readtime::Definitions
    )
      @holes = [] of QHole
    end

    # A shorthand for `QNumber.new(q.tag, value)`.
    private macro num(from value)
      QNumber.new(q.tag, {{value}})
    end

    # A shorthand for `QString.new(q.tag, value)`.
    private macro str(from value)
      QString.new(q.tag, {{value}})
    end

    # A shorthand for `QVector.new(q.tag, items)`.
    #
    # Casts each item of *items* to `Quote`.
    private macro vec(from items)
      QVector.new(q.tag, {{items}}.map &.as(Quote))
    end

    # A shorthand for `QTrue.new(q.tag)`.
    private macro true!
      QTrue.new(q.tag)
    end

    # A shorthand for `QFalse.new(q.tag)`.
    private macro false!
      QFalse.new(q.tag)
    end

    # Expands to `QFalse` if *value* is false, `QTrue` if not.
    private macro bool(from value)
      ({{value}}) == false ? false! : true!
    end

    # Returns the representation string for the given *quote*.
    #
    # The representation string is obtained by converting the
    # *quote* to string using `Unary.to_str`, then omitting it
    # (and inserting ellipsis at the end) if the string exceeds
    # `REPR_CAP`, and then wrapping in single quotes.
    private def repr(quote : Quote) : String
      it = to_str(quote).value
      it.size > REPR_CAP ? "'#{it[..REPR_CAP]}...'" : "'#{it}'"
    end

    # Returns the representation string for the given *quotes*.
    #
    # Applies `repr(quote)` to each quote of *quotes*, and
    # joins with commas.
    private def repr(quotes : Quotes) : String
      quotes.map { |quote| repr(quote) }.join(", ")
    end

    # Same as `Readtime::Unary.unary`, but dies on failure,
    # or if caught an `InvalidBigDecimalException`.
    def unary!(operator : String, operand : Quote) : Quote
      unary(operator, operand) || die(operand.tag,
        "could not apply '#{operator}' to #{repr(operand)}")
    rescue InvalidBigDecimalException
      die(operand.tag, "#{repr(operand)} is not a base-10 number")
    end

    # Same as `Readtime::Binary.binary`, but dies on failure, or
    # if caught an `InvalidBigDecimalException`, `OverflowError`,
    # or a `DivisionByZeroError`.
    def binary!(operator : String, left : Quote, right : Quote) : Quote
      binary(operator, left, right) || die(left.tag,
        "could not apply '#{operator}' to #{repr(left)}, #{repr(right)}")
    rescue InvalidBigDecimalException
      die(left.tag,
        "either #{repr(left)}, or #{repr(right)}, is an invalid base-10 number")
    rescue OverflowError
      die(left.tag,
        "'#{operator}': numeric overflow given #{repr(left)}, #{repr(right)}")
    rescue DivisionByZeroError
      die(left.tag,
        "'#{operator}': division by zero given #{repr(left)}, #{repr(right)}")
    end

    # Calls `eval(state, quote)` for each quote of *quotes*.
    def eval(state, quotes : Quotes)
      quotes.map do |quote|
        eval(state, quote)
      end
    end

    # Evaluates the given *quote* in a readtime envelope *state*
    # (see `Readtime::State`).
    #
    # It is important to understand that there is no visual
    # difference between an evaluated and an unevaluated
    # (raw) quote.
    #
    # In `eval`, a quote is simplified via readtime semantics,
    # but it still is a quote after all (sometimes the same
    # quote you put in, even; so **`copy` the bodies of loops**).
    #
    # It is the ephemeral reduction (and side effects produced,
    # of course) that make us distinguish evaluated and raw
    # quotes.
    #
    # There are quotes that look the same before and after
    # evaluation. We call them *homoiconic quotes*. You may
    # make any quote homoiconic with `quote(expression)` (you
    # can inline, too: `quote($a + $b)`).
    def eval(state, quote : Quote)
      case quote
      when QQuoteEnvelope,
           QNumber,
           QString,
           QRegex,
           QTrue,
           QFalse
        quote
      else
        die(quote.tag, "#{quote.class} not supported in readtime envelope")
      end
    end

    def eval(state, q : QVector)
      vec eval(state, q.items)
    end

    def eval(state, q : QSuperlocalTake)
      state.superlocal.take? || die(q.tag, "'_': could not borrow")
    end

    def eval(state, q : QSuperlocalTap)
      state.superlocal.tap? || die(q.tag, "'&_': could not borrow")
    end

    def eval(state, q : QReadtimeSymbol)
      die(q.tag,
        "there is no need to emphasize readtime symbols " \
        "in a readtime envelope: it's readtime anyway")
    end

    def eval(state, q : QRuntimeSymbol)
      state.definitions[q.value]? || die(q.tag,
        "readtime symbol not found: #{q.value}")
    end

    def eval(state, q : QUnary)
      unary!(q.operator, eval(state, q.operand))
    end

    def eval(state, q : QBinary)
      left = eval(state, q.left)

      # `false` being the only false value in the language,
      # really simplifies these kinds of things.
      if q.operator == "and"
        return left if left.is_a?(QFalse)
        return eval(state, q.right)
      elsif q.operator == "or"
        return left unless left.is_a?(QFalse)
        return eval(state, q.right)
      end

      binary!(q.operator, left, eval(state, q.right))
    end

    def eval(state, q : QCall)
      unless callee = q.callee.as?(QSymbol).try(&.value)
        die("illegal callee quote: #{q.callee.class}")
      end

      args = q.args

      loop do
        # Special-forms, like in Lisp, take the arguments raw.
        #
        # If callee is not one of the special forms, evaluate
        # the arguments and forward to `Readtime::Builtin`,
        # which either provides the implementation, or doesn't.
        case callee
        when "quote"
          return QQuoteEnvelope.new(q.tag, args.first? || break)
        else
          call = Readtime::Builtin.new(self, state, @reader, @parent)
          args = eval(state, args)
          return call.do(callee, args) || break
        end
      end

      die(q.tag, "argument/parameter mismatch for #{callee}: #{repr(args)}")
    end

    def eval(state, q : QAssign)
      unless target = q.target.as?(QRuntimeSymbol).try(&.value)
        die("unsupported assignment target: #{q.target.class}")
      end

      # There is no point in taking global assignment (:=)
      # into account here, as it only makes sense when there's
      # a scope stack; at readtime, there is no scope stack.
      state.definitions[target] = eval(state, q.value)
    end

    def eval(state, q : QDies)
      eval(state, q.operand)
      # Replicates Ven runtime semantics: false if didn't
      # die, true otherwise.
      false!
    rescue ReadError | TransformDeathException
      true!
    end

    def eval(state, q : QEnsure)
      value = eval(state, q.expression)
      value.false? ? die(q.tag, "ensure: got false") : value
    end

    def eval(state, q : QBlock)
      eval(state.with(borrow: true), q.body).last? || die(q.tag, "empty block")
    end

    def eval(state, q : QQueue)
      # Queue values are **outside** of readtime envelope, but
      # still inside expansion (hence the use of `transform`).
      if !@holes.empty?
        # If there are unfilled holes, we eject the first one,
        # and mutate its value with this queue's expression.
        @holes.shift.value = transform(q.value)
      else
        # If there are no holes, we append the value to the
        # state's queue, as expected.
        state.queue << transform(q.value)
      end

      # It was mutated by `transform`!
      q.value
    end

    def eval(state, q : QReturnExpression)
      # QReturnExpression, as in runtime Ven, just sets the
      # return value, i.e., without interrupting the flow.
      state.return = transform(q.value)
    end

    def eval(state, q : QReturnStatement)
      # QReturnStatement, as in runtime Ven, interrupts the
      # flow and returns out of this envelope immediately.
      raise ReturnException.new(transform(q.value))
    end

    def eval(state, q : QMapSpread)
      operand = eval(state, q.operand)

      if !operand.is_a?(QVector) || operand.items.size == 0
        return operand
      elsif operand.items.size < 2
        return operand.items.first
      end

      items = operand.items

      if q.iterative
        # Iterative map spreads do '.each' instead of '.map',
        # and return the original operand.
        items.each do |item|
          eval(state.with(item), q.operator.clone)
        end
      else
        items = items.map do |item|
          # Note how borrows originating from map spreads
          # are disabled.
          eval(state.with(item), q.operator.clone)
        end
      end

      vec items
    end

    def eval(state, q : QReduceSpread)
      operand = eval(state, q.operand)

      case operand
      when QQuoteEnvelope
        # Quote joining mode: e.g., `|and| quote([a, b, c])`
        # returns `a and b and c`.
        return operand unless contents = operand.quote.as?(QVector)

        contents.items.reduce do |memo, item|
          QBinary.new(q.tag, q.operator, memo, item)
        end
      when QVector
        # Readtime reduce mode: `|+| [1, 2, 3]` returns 6.
        return operand.items.first? || operand if operand.items.size < 2

        operand.items.reduce do |memo, item|
          binary!(q.operator, memo, item)
        end
      else
        operand
      end
    end

    def eval(state, q : QIf)
      condition = eval(state, q.cond)

      # The branch it chose to execute.
      branch = q.suc

      case condition
      when QTrue
      when QFalse
        branch = q.alt.as?(Quote) || return false!
      else
        # This produces the same behavior as in runtime Ven,
        # but may leave remnant superlocals unless consumed
        # by the corresponding branch. This is expected!
        state.superlocal.fill(condition)
      end

      eval(state, branch)
    end

    def eval(state, q : QEnsureTest)
      comment = to_str eval(state, q.comment)
      comment = comment.value.colorize.bold
      readtime = "(at readtime)".colorize.dark_gray
      puts "[#{q.tag.file}]: #{comment} #{readtime}"

      # *shoulds* will be an array of QTrue/QFalse, depending
      # on each individual should success.
      shoulds = eval(state, q.shoulds)

      shoulds.each do |should|
        return false! if should.false?
      end

      true!
    end

    def eval(state, q : QEnsureShould)
      failures = q.pad.compact_map do |test|
        value = eval(state, test)
        if value.false?
          # Write the failure if *value* is `QFalse`.
          "#{test.tag.file}:#{test.tag.line}: got #{repr(value)}"
        end
      end

      if failures.empty?
        puts " #{"✓".colorize.bold.green} #{q.section}"
      else
        puts " ❌ #{q.section}".colorize.bold.red
        failures.each do |failure|
          puts "\t◦ #{failure}"
        end
      end

      # Return whether there were any failures in this
      # particular should.
      bool failures.empty?
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

    def transform!(q : QQuoteEnvelope)
      q.quote
    end

    # Expands to the quote produced by the expression of the
    # readtime envelope.
    deftransform QReadtimeEnvelope do
      state = Readtime::State.new(@definitions)

      begin
        body = eval(state, quote.expression)
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
      if !state.queue.empty?
        return QBlock.new(quote.tag, transform(state.queue))
      elsif returned = state.return.as?(Quote)
        return transform(returned)
      end

      transform(body)
    end
  end
end
