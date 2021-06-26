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

    # The Proc returned by `mk_pattern`.
    #
    # You can call this Proc with the matchee of a pattern
    # match, and expect a quote that will do the match as
    # the result.
    alias PatternMaker = Proc(Quote, Quote)

    # The name of the filter hook (`[1, 2, 3 | _ > 5]` is
    # actually `__filter([1, 2, 3], () _ > 5)`.
    FILTER_HOOK = "__filter"

    @@symno = 0

    # Generates a symbol unique throughout a single instance
    # of Ven machinery.
    def gensym
      QRuntimeSymbol.new(QTag.void, "__temp#{@@symno += 1}")
    end

    # Pattern matches primitives (those where just an 'is'
    # will suffice)
    def mk_pattern(p : QNumber | QString | QRegex) : PatternMaker
      PatternMaker.new do |arg|
        QBinary.new(p.tag, "is", arg, p)
      end
    end

    # Pattern matches vectors (recursively).
    def mk_pattern(p : QVector) : PatternMaker
      PatternMaker.new do |arg|
        accesses = Quotes.new
        matchers = Array(PatternMaker).new

        # Go over the vector. Collect PatternMakers for items,
        # and item access expressions.
        p.items.each_with_index do |item, index|
          matchers << mk_pattern(item)
          accesses << QCall.new(item.tag, arg, [QNumber.new(item.tag, index.to_big_d).as(Quote)])
        end

        clauses = [
          # Make sure `arg is vec`:
          QBinary.new(p.tag, "is", arg, QRuntimeSymbol.new(p.tag, "vec")),
          # Make sure `#arg is #accesses`:
          QBinary.new(p.tag, "is",
            QUnary.new(p.tag, "#", arg),
            QNumber.new(p.tag, accesses.size.to_big_d)),
        ]

        # Make patterns for each of the item accesses. Concat
        # them with the clauses.
        clauses += matchers.zip(accesses).map do |matcher, access|
          matcher.call(access)
        end

        # Compute the initial memo: take the first two clauses
        # and QBinary-and them.
        memo = QBinary.new(clauses[0].tag, "and",
          clauses[0],
          clauses[1])

        # Reduce the remaining clauses, and return them.
        clauses[2..].reduce(memo) do |memo, clause|
          QBinary.new(clause.tag, "and", memo, clause)
        end
      end
    end

    # Death fallback for unsupported quotes.
    def mk_pattern(p : Quote)
      raise ReadError.new(p.tag, "#{p.class} is not supported in patterns")
    end

    # Returns the corresponding pattern lambda for a
    # pattern shell.
    def transform(q : QPatternShell)
      arg = gensym
      # 'and' the resulting clauses with `arg`, so that if
      # matched successfully, this lambda returns <arg> -
      # and otherwise, false.
      QLambda.new(q.tag, [arg.value],
        QBinary.new(q.tag, "and",
          mk_pattern(q.pattern).call(arg), arg), false)
    end

    # Transforms a vector filter, or, if there is none, passes.
    #
    # ```ven
    # [1, 2, 3 | _ > 5];
    #
    # # Becomes:
    #
    # __filter([1, 2, 3], () _ > 5);
    # ```
    def transform(q : QVector)
      q.items = transform(q.items)
      unless filter = transform(q.filter)
        return q
      end

      # Unless the filter is a lambda already, or if it's a
      # symbol (which implies it stands for a lambda), make
      # a lambda that wraps around it.
      lambda =
        case filter
        when QSymbol, QLambda
          filter
        else
          QLambda.new(filter.tag, [] of String, filter, false)
        end

      # And construct a call to the filter hook.
      QCall.new(q.tag, QRuntimeSymbol.new(q.tag, FILTER_HOOK), [q, lambda])
    end

    # Transforms an immediate box statement into a box
    # statement followed by an instantiation of it, after
    # which the box's name is bound to the box instance:
    #
    # ```ven
    # immediate box Foo;
    #
    # # Becomes:
    #
    # box Foo;
    # Foo := Foo();
    # ```
    def transform(q : QImmediateBox)
      unless q.box.params.empty?
        raise ReadError.new(q.tag,
          "impossible to immediately instantiate a parametric box")
      end

      QGroup.new(q.tag,
        [q.box,
         QAssign.new(q.tag, q.box.name,
           QCall.new(q.tag,
             q.box.name,
             Quotes.new), true)])
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

    # Makes an instance of this class, uses it to transform
    # *quotes* **in-place**, and disposes the instance.
    #
    # Returns the transformed quotes (although they are
    # mutated in-place anyways).
    def self.transform(quotes : Quotes)
      new.transform(quotes)
    end
  end
end
