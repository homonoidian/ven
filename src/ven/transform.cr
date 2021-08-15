module Ven
  # Transformation is the second stage of Ven interpretation.
  #
  # It transforms `QPatternEnvelope`s into the corresponding
  # `QLambda`s, expands protocol macros, etc.
  class Transform < Ven::Suite::Transformer
    include Suite

    # Consensus filter hook name. For example, `[1, 2, 3 | _ > 5]`
    # is transformed into `FILTER_HOOK([1, 2, 3], () _ > 5)`
    FILTER_HOOK = "__filter"

    # Consensus access assign hook name. For example, `a[b] = c`
    # is transformed into `ACCESS_ASSIGN_HOOK(a, c, b)`
    ACCESS_ASSIGN_HOOK = "__access_assign"

    @@symno = 0

    # Generates a unique runtime symbol with the given *tag*.
    #
    # The default *tag* is the void tag, which means you won't
    # get accurate location reports about the symbol.
    def gensym(tag = QTag.void)
      QRuntimeSymbol.new(tag, "__temp#{@@symno += 1}")
    end

    # Transforms this vector filter expression into a consensus
    # filter hook call expression (see `FILTER_HOOK`).
    #
    # ```ven
    # # Before:
    #
    # [1, 2, 3 | _ > 5];
    #
    # # After:
    #
    # __filter([1, 2, 3], () _ > 5);
    # ```
    def transform!(q : QFilterOver)
      # Unless the filter is a lambda already, or if it's a
      # symbol (which implies it stands for a lambda), make
      # a lambda that wraps around it.
      case q.filter
      when QSymbol, QLambda
        lambda = q.filter
      else
        lambda = QLambda.new(q.tag, [] of String, q.filter, false)
      end

      # And pass it to the consensus filter hook.
      QCall.new(q.tag, QRuntimeSymbol.new(q.tag, FILTER_HOOK), [q.vector, lambda])
    end

    # Transforms an immediate box statement into a box
    # statement followed by an instantiation of it, after
    # which the box's name is rebound to the box instance:
    #
    # ```ven
    # # Before:
    #
    # immediate box Foo;
    #
    # # After:
    #
    # box Foo;
    # Foo := Foo();
    # ```
    def transform!(q : QImmediateBox)
      unless q.box.params.empty?
        die("impossible to immediately instantiate a parametric " \
            "box (cannot pass arguments)")
      end

      # <box name>()
      instance = QCall.new(q.tag, q.box.name, Quotes.new)

      QGroup.new(q.tag, [
        q.box,
        # <box name> := <instance>
        QAssign.new(q.tag, q.box.name, instance, global: true),
      ])
    end

    # Transforms an access-assign expression into a call to
    # the consensus access-assign hook call expression (see
    # `ACCESS_ASSIGN_HOOK`).
    #
    # ```ven
    # # Before:
    #
    # a[b] = c
    #
    # # After:
    #
    # __access_assign(a, c, b)
    #
    # # Before:
    #
    # a[b][c] = d
    #
    # # After
    #
    # __access_assign(a[b], d, c)
    # ```
    def transform!(q : QAssign)
      return q unless target = q.target.as?(QAccess)

      QCall.new(q.tag, QRuntimeSymbol.new(q.tag, ACCESS_ASSIGN_HOOK),
        [target.head, q.value] + target.args)
    end

    # Transforms an access-assign expression into a call to
    # the consensus access-assign hook call expression (see
    # `ACCESS_ASSIGN_HOOK`).
    #
    # ```ven
    # # Before:
    #
    # a[b] += c
    #
    # # After:
    #
    # __access_assign(a, a[b] + c, b)
    #
    # # Before:
    #
    # a[b][c] += d
    #
    # # After:
    #
    #  __access_assign(a[b], a[b][c] + d, c)
    # ```
    def transform!(q : QBinaryAssign)
      return q unless target = q.target.as?(QAccess)

      QCall.new(q.tag, QRuntimeSymbol.new(q.tag, ACCESS_ASSIGN_HOOK),
        [target.head, QBinary.new(q.tag, q.operator, target, q.value)] + target.args)
    end
  end
end
