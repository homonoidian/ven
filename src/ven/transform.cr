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

    # Implements the call-assign protocol hook.
    #
    # ```
    # x(0) = 1 is __call_assign(x, 1, 0);
    # x("foo")(0) = 1 is __call_assign(x("foo"), 1, 0);
    # ```
    def transform(q : QAssign)
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
