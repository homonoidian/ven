module Ven
  class Transform < Suite::Transformer
    # Consensus vector type name. Used by the pattern generator
    # in `subject is <>` expressions.
    VEC = "vec"

    # Consensus map type name. Used by the pattern generator
    # in `subject is <>` expressions.
    MAP = "map"

    # Consensus map keys field name. Used by the pattern
    # generator in `key in subject.keys` expressions.
    MAP_KEYS = "keys"

    # Represents a pattern context.
    record Context, env = {} of String => Quote

    # Same as writing `QNumber(tag, value.to_big_d)`
    private macro num(value, tag = QTag.void)
      QNumber.new({{tag}}, {{value}}.to_big_d)
    end

    # Same as writing `QRuntimeSymbol.new(tag, value.to_s)`
    private macro sym(value, tag = QTag.void)
      QRuntimeSymbol.new({{tag}}, {{value}}.to_s)
    end

    # A shorthand for writing the following Ven: `<left> is <right>`
    private macro is(left, right)
      %left = {{left}}

      QBinary.new(%left.tag, "is", %left, {{right}})
    end

    # A shorthand for writing the following Ven: `<left> in <right>`
    private macro in?(left, right)
      %left = {{left}}

      QBinary.new(%left.tag, "in", %left, {{right}})
    end

    # A shorthand for writing the following Ven: `<operand>[<index>]`.
    private macro nth(operand, index)
      %operand = {{operand}}

      QAccess.new(%operand.tag, %operand, [{{index}}] of Quote)
    end

    # A shorthand for writing the following Ven: `#<operand>`.
    private macro len(operand)
      %operand = {{operand}}

      QUnary.new(%operand.tag, "#", %operand)
    end

    # A shorthand for writing the following Ven: `<symbol> = <value>`.
    private macro local(symbol, value)
      %symbol = {{symbol}}

      QAssign.new(%symbol.tag, %symbol, {{value}}, global: false)
    end

    # A shorthand for writing the following Ven: `<operand>.keys`,
    # assuming *operand* is a map. See also `MAP_KEYS`.
    private macro keys_of(operand)
      %operand = {{operand}}

      QAccessField.new(%operand.tag, %operand,
        [FAImmediate.new(sym MAP_KEYS)] of FieldAccessor)
    end

    # Joins *left*, *right* with an *operator* `QBinary`.
    #
    # If both *left* and *right* are available, makes the
    # appropriate `QBinary`. If one of *left*, *right* is
    # available, returns that. Otherwise, returns nil.
    protected def join(operator : String, left : MaybeQuote, right : MaybeQuote)
      left && right ? QBinary.new(left.tag, operator, left, right) : left || right
    end

    # Compacts the *quotes*, and then reduces them with an
    # *operator* `QBinary`.
    protected def join(operator : String, quotes : Array(MaybeQuote))
      quotes.compact.reduce? do |memo, quote|
        QBinary.new(quote.tag, operator, memo, quote)
      end
    end

    # Yields each quote of *quotes*, and its index, to the
    # block, and `join`s the resulting array of quotes.
    #
    # Allows the block to return nil, in which case the quote
    # will be ignored.
    protected def join(operator : String, quotes : Array(MaybeQuote))
      join(operator, quotes.map_with_index { |*args|
        (yield *args).as(MaybeQuote)
      })
    end

    # Expands to `*subject* is *pattern*`.
    def match(ctx, subject, pattern : QNumber | QString | QRegex)
      is(subject, pattern)
    end

    # Assigns symbol *pattern* to *subject* in the pattern
    # environment if there is no such *pattern* there, or
    # to the subject assigned to *pattern* in the pattern
    # environment. The latter is called (subject) *parity*.
    #
    # Expands to nothing in the first case, and to the
    # corresponding quote in case of parity.
    #
    # ```ven
    # # Given the following parity: [a a], the two 'a's are
    # expressed by (where `$` is the vector subject):
    #   $[0] is $[1]
    # ```
    def match(ctx, subject, pattern : QRuntimeSymbol)
      if parity = ctx.env[pattern.value]?
        return is(subject, parity)
      end

      ctx.env[pattern.value] = subject

      nil
    end

    # Escapes the pattern semantics, and expands to
    # `*subject* is *pattern.pattern*`.
    #
    # Dies on triple escape.
    def match(ctx, subject, pattern : QPatternEnvelope)
      # Catch triple escapes: `'''foo`
      if pattern.pattern.is_a?(QPatternEnvelope)
        die("redundant \"'\": did you add it mistakenly?")
      end

      is(subject, pattern.pattern)
    end

    # Makes sure *subject* is of the vector type (`VEC`), and
    # of the same size as *pattern*, and then recurses on the
    # pairs of *subject*, *pattern* items, respectively.
    #
    # Expands to (where `$` stands for *subject*):
    #
    # ```ven
    #   $ is vec and #$ is <#pattern>
    #     and $[0] is <pattern[0]>
    #     and $[1] is <pattern[1]>
    #     and $[2] is <pattern[2]>
    #     # ... etc
    # ```
    def match(ctx, subject, pattern : QVector)
      # The body checks match the *pattern* vector items
      # against the actual *subject* items.
      body = join("and", pattern.items) do |subpattern, index|
        match(ctx, nth(subject, num index, pattern.tag), subpattern)
      end

      join("and", [
        # The identity checks make sure *subject* is a vector,
        # and is of the expected size.
        is(subject, sym VEC),
        is(len(subject), num pattern.items.size),
      ] of MaybeQuote << body)
    end

    # Makes sure *subject* is of the map type (`MAP`), and
    # goes over the keys of *pattern*. If *subject* does not
    # have a key that is in *pattern*, it fails. If it does,
    # it recurses on the value with its subject being the
    # appropriate field access.
    #
    # Expands to (where `$` stands for *subject*):
    #
    # ```ven
    #   $ is map
    #     # If <key of pattern> is a string:
    #     and (<key of pattern> in $)
    #     and <recur(ctx, $[key], pattern[key])>
    #     # If <key of pattern> is anything else:
    #     and (__tempN = <key of pattern> in $.keys)
    #     and <recur(ctx, $[__tempN], pattern[key])>
    #     # ... etc
    # ```
    def match(ctx, subject, pattern : QMap)
      body = pattern.keys.zip(pattern.vals).map do |key, val|
        # The semantic objective of the match body is to make
        # sure the *subject* has the given key, and to transfer
        # control to the corresponding value.
        if key.is_a?(QString)
          join("and",
            # Whether the key is in the subject map.
            in?(key, subject),
            # If it is, go and match value with the item
            # being the subject.
            match(ctx, nth(subject, key), val),
          )
        else
          join("and",
            # Store the found key (if any) in a variable, so
            # no such searches are made in the value.
            local(found = gensym(key.tag), in?(key, keys_of subject)),
            # If found, recurse on the corresponding value.
            match(ctx, nth(subject, found), val),
          )
        end
      end

      join("and",
        # Make sure the subject is a map, and execute
        # the match body.
        [is(subject, sym MAP)] of MaybeQuote << join("and", body)
      )
    end

    # Semantically the same as `QRuntimeSymbol`: assigns to
    # *subject* in the pattern environment. Expands to the
    # right-hand side (the assignment 'value'). Right-hand
    # side is expanded *before* constraining *subject*,
    # thus, shadowing works as expected: `'[a (a = [a 1])]`
    # matches `[1 [1 1]]`, `[2 [2 1]`, etc., and defines
    # `a` as the vector: `[1 1]`, `[2 1]` respectively.
    def match(ctx, subject, pattern : QAssign)
      quote = match(ctx, subject, pattern.value)

      # At this point, it is safe to assume the assignment
      # target is always a `QRuntimeSymbol`.
      ctx.env[pattern.target.as(QRuntimeSymbol).value] = subject

      quote
    end

    # Recurses on the left-hand side of the *pattern*, and
    # then on the right-hand side, *but only if it is another
    # binary operation*, and the operator is a junction (i.e.,
    # either `and`, or `or`). Otherwise, leaves the right-hand
    # side untouched. Expands to `<*pattern>`, *unless the left-
    # hand side was a symbol*. In that case, substitutes the
    # symbol with the *subject* in the expansion.
    #
    # ```ven
    # # If left is not a symbol, and right is a junction:
    # <recur(pattern.left)> <pattern.operator> <recur(pattern.right)>
    # # If left is not a symbol, and right is not a junction:
    # <recur(pattern.left)> <pattern.operator> <pattern.right>
    # # If left is a symbol, and right is a junction:
    # <subject> <pattern.operator> <recur(pattern.right)>
    # # If left is a symbol, and right is not a junction:
    # <subject> <pattern.operator> <pattern.right>
    # ```
    def match(ctx, subject, pattern : QBinary)
      left = match(ctx, subject, pattern.left) || subject

      # If this is a junction, and the right-hand side of the
      # pattern is another binary expression, recurse.
      if pattern.operator.in?("and", "or") && pattern.right.is_a?(QBinary)
        right = match(ctx, subject, pattern.right)
      else
        right = pattern.right
      end

      join(pattern.operator, left, right)
    end

    # Ignores the subject.
    def match(ctx, subject, pattern : QSuperlocalTake)
      nil
    end

    # Fallback: dies of unsupported *pattern*.
    def match(ctx, subject, pattern)
      die("#{pattern.class} is not supported in patterns")
    end

    # Transforms a `QPatternEnvelope` into a pattern lambda.
    deftransform for: QPatternEnvelope do
      context = Context.new
      subject = gensym(quote.tag)

      # This generates the match (aka verification) body, and
      # incidentally populates the context's env.
      pattern = match(context, subject, quote.pattern)

      # And this populates the assignments map, which is the
      # only way to obtain the match results.
      assigns = QMap.new(quote.tag, Quotes.new, Quotes.new)

      context.env.each do |key, value|
        # Hash guarantees key uniqueness, no superfluous
        # pushes will be made.
        assigns.keys << QString.new(value.tag, key)
        assigns.vals << value
      end

      # Conjoin the pattern and the environment assignments.
      # If the pattern fails, no assignments are going to be
      # made, and it'll jump straight out of the lambda.
      QLambda.new(quote.tag, [subject.value],
        join("and", pattern, assigns), slurpy: false)
    end
  end
end
