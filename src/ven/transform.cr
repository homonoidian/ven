module Ven
  # > There are things in this world which are easier worked
  # > with when you transform them, than when you try to deal
  # > with them virgin.
  #
  # This is the to-do second stage of Ven interpretation. It
  # will transform QPatterns into QLambdas, expand protocol
  # macros (e.g., `|a| b` into `spread((_) a, b)`), etc. Maybe
  # something else, too. Or nothing at all.
  class Transform < Ven::Suite::Transformer
    include Suite

    @@symno = 0

    # Generates a symbol unique throughout a single run
    # of Ven.
    def gensym
      QRuntimeSymbol.new(QTag.void, "__temp#{@@symno += 1}")
    end

    # Constructs a pattern lambda for matching over number
    # or a string.
    def to_pattern_lambda(p : QNumber | QString)
      arg = gensym

      QLambda.new(p.tag, [arg.value],
        QBinary.new(p.tag, "is", arg, p), false)
    end

    # Constructs a pattern lambda for matching over vectors.
    #
    # Do note that the 'algorithm' used here produces very
    # long, nested and heavyweight lambdas, meaning it has
    # extremely poor performance in almost all cases.
    def to_pattern_lambda(p : QVector)
      arg = gensym

      matchers = Quotes.new
      accesses = Quotes.new

      # 1. Go over the vector:
      #   1.1 Collect matchers (match lambdas);
      #   1.2 Collect [item] accesses.
      p.items.each_with_index do |item, index|
        matchers << to_pattern_lambda(item)
        accesses << QCall.new(item.tag, arg.as(Quote), [QNumber.new(item.tag, index.to_big_d).as(Quote)])
      end

      clauses = [
        # Make sure `arg is vec`:
        QBinary.new(p.tag, "is", arg, QRuntimeSymbol.new(p.tag, "vec")),
        # Make sure `#arg is #accesses`:
        QBinary.new(p.tag, "is",
          QUnary.new(p.tag, "#", arg),
          QNumber.new(p.tag, accesses.size.to_big_d)),
      ]

      clauses += matchers.zip(accesses).map do |matcher, access|
        QCall.new(access.tag, matcher, [access])
      end

      # Compute the memo: take the first two clauses and
      # QBinary/and them.
      memo = QBinary.new(clauses[0].tag, "and",
        clauses[0],
        clauses[1])

      joint = clauses[2..].reduce(memo) do |memo, clause|
        QBinary.new(clause.tag, "and", memo, clause)
      end

      # Then reduce the rest of the clauses.
      QLambda.new(p.tag, [arg.value], joint, false)
    end

    # Death fallback for pattern lambda construction.
    def to_pattern_lambda(p : Quote)
      raise ReadError.new(p.tag, "#{p.class} is not supported in patterns")
    end

    # Returns the corresponding pattern lambda for a
    # pattern shell.
    def transform(q : QPatternShell)
      to_pattern_lambda(q.pattern)
    end

    # Dies of readtime symbol leak.
    #
    # I know this is not the place where we should catch
    # these, but where else?
    def transform(q : QReadtimeSymbol)
      raise ReadError.new(q.tag, "readtime symbol leaked")
    end

    # Implements the call-assign protocol hook.
    #
    # ```
    # x(0) = 1 is __call_assign(x, 1, 0);
    # x("foo")(0) = 1 is __call_assign(x("foo"), 1, 0);
    # ```
    def transform(q : QAssign)
      q.target = transform(q.target)
      q.value = transform(q.value)
      return q unless target = q.target.as?(QCall)

      QCall.new(q.tag, QRuntimeSymbol.new(q.tag, "__call_assign"),
        [target.callee, q.value] + target.args)
    end

    # Implements the call-assign protocol hook.
    #
    # ```
    # x(0) += 1 is __call_assign(x, x(0) + 1, 0)
    # x("foo")(0) += 1 is __call_assign(x("foo"), x("foo")(0) + 1, 0)
    # ```
    def transform(q : QBinaryAssign)
      q.target = transform(q.target)
      q.value = transform(q.value)
      return q unless target = q.target.as?(QCall)

      QCall.new(q.tag,
        QRuntimeSymbol.new(q.tag, "__call_assign"),
        [target.callee,
         QBinary.new(q.tag, q.operator,
           target,
           q.value)] + target.args)
    end

    # Makes an instance of this class, transforms *quotes*,
    # uses it to transform *quotes* **in-place**, and disposes
    # the instance immediately afterwards.
    #
    # Returns the transformed quotes (although they are mutated
    # in-place anyways).
    def self.transform(quotes : Quotes)
      new.transform(quotes)
    end
  end
end
