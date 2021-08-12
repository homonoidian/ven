module Ven
  # Transformation is the second stage of Ven interpretation.
  #
  # Say, it transforms `QPatternEnvelope`s into the corresponding
  # `QLambda`s, expands protocol macros (ones like the filter protocol
  # macro: `[1, 2, 3 | _ > 2]` into `__filter([1, 2, 3], (() _ > 2))`,
  # catches readtime symbols that got outside of the reader, etc.
  class Transform < Ven::Suite::Transformer
    include Suite

    # Takes the subject, and the environment (a map to write
    # the variables to), and, when `.call`ed, returns a `Quote`
    # that will, at runtime, perform the appropriate match op.,
    # resulting either in false, or in the environment.
    alias Pattern = Proc(Quote, QRuntimeSymbol, Quote)

    # Consensus vector type name. Used by the pattern generator
    # as the right-hand side of a subject-is expression.
    VEC_TYPE = "vec"

    # Consensus map type name. Used by the pattern generator
    # as the right-hand side of a subject-is expression.
    MAP_TYPE = "map"

    # Consensus map keys field name. Used by the pattern
    # generator as the right-hand side of a against-key-
    # in expression.
    MAP_KEYS = "keys"

    # Consensus filter hook name. For example, `[1, 2, 3 | _ > 5]`
    # is transformed into `<FILTER_HOOK_NAME>([1, 2, 3], () _ > 5)`)
    FILTER_HOOK = "__filter"

    # Consensus access assign hook name. For example, `a[b] = c`
    # is transformed into `<ACCESS_ASSIGN_HOOK_NAME>(a, c, b)
    ACCESS_ASSIGN_HOOK = "__access_assign"

    @@symno = 0

    # Generates a unique runtime symbol. Note that the `QTag`
    # of this symbol is void.
    def gensym
      QRuntimeSymbol.new(QTag.void, "__temp#{@@symno += 1}")
    end

    # Basic pattern match: will generate `<subject> is <against>`.
    def pattern(against : QNumber | QString | QRegex) : Pattern
      Pattern.new do |subject, _env|
        QBinary.new(against.tag, "is", subject, against)
      end
    end

    # A pattern envelope inside a pattern envelope escapes
    # pattern semantics: `'('num)` (you can shorten it like
    # so: `''num`) translates to `<subject> is num`.
    def pattern(against : QPatternEnvelope) : Pattern
      Pattern.new do |subject, _env|
        if against.pattern.is_a?(QPatternEnvelope)
          die("redundant \"'\"; did you add it mistakenly?")
        end

        QBinary.new(against.tag, "is", subject, against.pattern)
      end
    end

    # Assigns symbol *against* to the subject in the
    # pattern environment.
    def pattern(against : QRuntimeSymbol) : Pattern
      tag = against.tag

      Pattern.new do |subject, env|
        # Make the access handle: `env["<against>"]`. Say,
        # given `'a`, this will produce `env["a"]`.
        access = QAccess.new(tag, env, [
          QString.new(tag, against.value).as(Quote),
        ])

        # Make an access-assignment using the handle, and
        # assign to the subject. Given `'a`, this will
        # produce `env["a"] = <subject>`.
        assign = QAssign.new(tag, access, subject, global: false)

        # Transform to turn the access-assign expression into
        # the access assign hook.
        transform!(assign)
      end
    end

    # If the left-hand side of *against* is a symbol, substitutes
    # that symbol with the subject, making sure the expression
    # returns true, and then assigns that symbol to the subject.
    # `'(a is 1)` translates to `<subj> is 1 and a = <subj>`.
    #
    # The left-hand side may not be a symbol **if the operator
    # is either `and`, or `or`**. In this case, both `left` and
    # `right` are made into patterns, and then joined (conjoined
    # or disjoined, depending on the operator). Because of this,
    # `'(a < 1 and a > 5)` translates to
    #
    # `(<subj> < 1 and <subj> > 5) and a = <subj>`
    def pattern(against : QBinary) : Pattern
      tag = against.tag

      Pattern.new do |subject, env|
        left = against.left
        right = against.right

        # Handles the simplest cases: `foo is num`, `bar is 10`,
        # `baz < 15`, etc.
        if left.is_a?(QRuntimeSymbol)
          # Say, for `foo is num`, produces:
          #
          # `<subject> is num and env["foo"] = <subject>`
          #
          # The question of whether this is better than
          #
          # `(env["foo"] = <subject>) is num`
          #
          # ... remains open for me.
          next QBinary.new(tag, "and",
            QBinary.new(tag, against.operator, subject, right),
            # Assign in the environment.
            pattern(left).call(subject, env),
          )
        elsif left.is_a?(QSuperlocalTake)
          # Simply match, without assigning to the
          # left-hand side.
          next QBinary.new(tag, against.operator, subject, right)
        end

        unless against.operator.in?("and", "or")
          die("invalid binary pattern")
        end

        lhs_sym = left.as?(QBinary).try &.left.as?(QRuntimeSymbol)
        rhs_sym = right.as?(QBinary).try &.left.as?(QRuntimeSymbol)

        # Handles more complex cases: `(a is b) and (c is d)`,
        # `(a < 10) and '(foo())`, etc.
        unless lhs_sym && rhs_sym && lhs_sym.value == rhs_sym.value
          next QBinary.new(tag, against.operator,
            pattern(left).call(subject, env),
            pattern(right).call(subject, env),
          )
        end

        left = left.as(QBinary)
        right = right.as(QBinary)

        # The most complex cases, where patterns have binaries
        # with identical symbols at left-hand side:
        #
        # `(a < 1) and (a > 2)`
        #
        # Make their 'left' and 'right' subjects instead of
        # symbols to do less work & recursion (although this
        # fails if got a chain of more than two and/or-s).
        left = QBinary.new(left.tag, left.operator, subject, left.right)
        right = QBinary.new(right.tag, right.operator, subject, right.right)

        # Say, for `(a < 1) and (a > 2)`, this produces:
        #
        # `(<subj> < 1) and (<subj> > 2) and env["a"] = <subj>`
        QBinary.new(tag, "and",
          QBinary.new(tag, against.operator, left, right),
          # Assign in the environment.
          pattern(lhs_sym).call(subject, env),
        )
      end
    end

    # Same as `pattern(against : QRuntimeSymbol)`, but explicit
    # about the assignee. Non-symbolic targets are unsupported.
    def pattern(against : QAssign) : Pattern
      unless target = against.target.as?(QRuntimeSymbol)
        die("assignment pattern: non-symbolic targets are unsupported")
      end

      Pattern.new do |subject, env|
        QBinary.new(against.tag, "and",
          # Whether the subject matches against the assign
          # right-hand side.
          pattern(against.value).call(subject, env),
          # Assign in the environment.
          pattern(target).call(subject, env),
        )
      end
    end

    # Matches each item of the *against* vector with the
    # corresponding item of the subject vector.
    def pattern(against : QVector) : Pattern
      tag = against.tag

      Pattern.new do |subject, env|
        accesses = Quotes.new
        matchers = Array(Pattern).new

        # Go over the vector. Gather `Pattern`s for items, as
        # well as access expressions.
        against.items.each_with_index do |item, index|
          matchers << pattern(item)
          accesses << QAccess.new(item.tag, subject,
            [QNumber.new(item.tag, index.to_big_d).as(Quote)])
        end

        clauses = [
          # Make sure `subject is vec`:
          QBinary.new(tag, "is", subject,
            QRuntimeSymbol.new(tag, VEC_TYPE)).as(Quote),
          # Make sure `#subject is #accesses`:
          QBinary.new(tag, "is",
            QUnary.new(tag, "#", subject),
            QNumber.new(tag, accesses.size.to_big_d)).as(Quote),
        ]

        # Call `Pattern` with the corresponding item access
        # being the subject. Add the result to clauses.
        matchers.zip(accesses) do |matcher, access|
          clauses << matcher.call(access, env)
        end

        # Compute the setup memo: take the first two clauses
        # and `and` them.
        memo = QBinary.new(clauses[0].tag, "and",
          clauses[0],
          clauses[1])

        # Reduce the remaining clauses, and return them.
        clauses[2..].reduce(memo) do |memo, clause|
          QBinary.new(clause.tag, "and", memo, clause)
        end
      end
    end

    # Matches each value of the subject map against the
    # corresponding value of the *against* map.
    def pattern(against : QMap) : Pattern
      tag = against.tag

      Pattern.new do |subject, env|
        clauses = [
          # Make sure the subject is a map.
          QBinary.new(tag, "is", subject,
            QRuntimeSymbol.new(tag, MAP_TYPE)).as(Quote),
        ]

        against.keys.each_with_index do |key, index|
          access = gensym

          # If this match key is not a string (e.g., regex),
          # generate an additional `in` which fetches the
          # matching key (or returns false), failing
          # whole match.
          unless key.is_a?(QString)
            key = QBinary.new(tag, "in",
              key,
              # <subject>.keys
              QAccessField.new(tag, subject,
                [FAImmediate.new(QRuntimeSymbol.new(tag, MAP_KEYS))
                  .as(FieldAccessor)]))
          end

          # Returns the value if the subject has the given
          # *key*, otherwise false.
          #
          # <key> in <subject>
          value = QBinary.new(tag, "in", key, subject)

          # Make sure the key exists, and store it in a variable.
          # Access expressions are somewhat expensive when used
          # in large quantities; variable lookup should generally
          # be cheaper.
          clauses << QBinary.new(tag, "and",
            # <access> = <key> in <subject>
            QAssign.new(tag, access, value, global: false),
            # ... and <pattern-for(access)>
            pattern(against.vals[index]).call(access, env),
          )
        end

        clauses.reduce do |memo, clause|
          QBinary.new(tag, "and", memo, clause)
        end
      end
    end

    # Noop that expands to true: `[1 _ 3]`. It should be
    # optimized away at later stages.
    def pattern(against : QSuperlocalTake) : Pattern
      Pattern.new do |_subject, _env|
        QTrue.new(against.tag)
      end
    end

    # Death fallback for unsupported quotes.
    def pattern(against : Quote)
      die("#{against.class} is not supported in patterns")
    end

    # Returns the corresponding pattern lambda for a pattern
    # envelope.
    deftransform for: QPatternEnvelope do
      arg = gensym
      env = gensym

      # Generate the pattern match expression. Variable captures
      # are going to be written (**at runtime**) into *env*.
      pattern = pattern(quote.pattern).call(arg, env)

      QLambda.new(quote.tag, [arg.value],
        QBlock.new(quote.tag, [
          # <env> = %{};
          QAssign.new(quote.tag, env,
            QMap.new(quote.tag,
              Quotes.new,
              Quotes.new),
            global: false),
          # <pattern> and <env>
          QBinary.new(quote.tag, "and", pattern, env),
        ]), slurpy: false)
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
