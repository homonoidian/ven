require "./suite/*"

module Ven
  class Machine < Suite::Visitor
    include Suite

    # Maximum call depth (see `call`). Release builds allow
    # deeper call nesting.
    MAX_CALL_DEPTH =
      {% if flag?(:release) %}
        1024
      {% else %}
        512
      {% end %}

    # Ven booleans are structs (copy on use). There is no
    # need for the `.new`s everywhere (?)
    B_TRUE = MBool.new(true)
    B_FALSE = MBool.new(false)

    getter world

    def initialize
      @world = uninitialized World
      @context = uninitialized Context
    end

    def world=(@world : World)
      @context = @world.context
    end

    # Converts a Crystal boolean into an `MBool`.
    private macro to_bool(bool)
      {{bool}} ? B_TRUE : B_FALSE
    end

    # Sets *value*'s `truth` to true and returns the value
    # back if *condition* was true. Otherwise, returns `B_FALSE`.
    #  See `Model.truth?`.
    private macro truthy(value, if condition)
      if {{condition}}
        truthy {{value}}
      else
        B_FALSE
      end
    end

    # Sets *value*'s `truth` to true and returns the value
    # back. See `Model.truth?`.
    private macro truthy(value)
      %value = {{value}}
      %value.truth = true
      %value
    end

    # If *condition* is Crystal true, returns *left*; otherwise,
    # returns **Ven boolean** false. *condition* may be omitted;
    # in that case, *left* itself will be used as the condition.
    #
    # NOTE: if *condition* is true but *left* is semantically
    # false, returns B_TRUE.
    private macro may_be(left, if condition = nil)
      {% if condition %}
        if {{condition}}
          (%this = {{left}}).true? ? %this : B_TRUE
        else
          B_FALSE
        end
      {% else %}
        (%this = {{left}}) ? %this.not_nil! : B_FALSE
      {% end %}
    end

    # Constrains *names* to *types*. Evaluates the *types*,
    # making sure that each returns a type and dying if it
    # does not. Uses `MType::ANY` for the missing types, if
    # there are any.
    def constrained(names : Array(String), by types : Quotes)
      constraint = MType::ANY

      names.zip?(types).map do |name, type|
        unless type.nil?
          constraint = visit(type)
        end

        ConstrainedParameter.new(name, constraint)
      end
    end

    # Calls `Context.fetch` with *name* and dies if not found.
    def fetch(name : String)
      @context.fetch(name) || die("symbol '#{name}' not found")
    end

    # Dies of runtime error with *message*. Constructs a
    # traceback where the top entry is the outermost call,
    # and the bottom entry the caller of death itself.
    # Issues a `<unit>` traceback entry to display the last
    # node in execution, unless it duplicates the last traceback
    # entry.
    def die(message : String)
      traces = @context.traces.dup

      unless traces.last?.try(&.tag) == @last.tag
        traces += [Trace.new(@last.tag, "<unit>")]
      end

      raise RuntimeError.new(@last.tag, message, traces)
    end

    def visit!(q : QSymbol)
      fetch(q.value)
    end

    def visit!(q : QNumber)
      Num.new(q.value)
    end

    def visit!(q : QString)
      Str.new(q.value)
    end

    def visit!(q : QRegex)
      MRegex.new(q.value)
    rescue ArgumentError
      die("regex syntax error: invalid PCRE literal: `#{q.value}`")
    end

    def visit!(q : QVector)
      Vec.new(visit(q.items))
    end

    def visit!(q : QUPop)
      @context.u?
    rescue IndexError
      die("'_' used outside of context: underscores stack is empty")
    end

    def visit!(q : QURef)
      @context.us.last
    rescue IndexError
      die("'&_' used outside of context: underscores stack is empty")
    end

    def visit!(q : QUnary)
      unary(q.operator, visit(q.operand))
    end

    def visit!(q : QBinary)
      binary(q.operator, visit(q.left), visit(q.right))
    end

    def visit!(q : QIntoBool)
      visit(q.value).to_bool
    end

    def visit!(q : QReturnDecrement)
      target = fetch(q.target)
      result = binary("-", target, Num.new 1)
      @context.define(q.target, result)

      target
    end

    def visit!(q : QReturnIncrement)
      target = fetch(q.target)
      result = binary("+", target, Num.new 1)
      @context.define(q.target, result)

      target
    end

    def visit!(q : QQuote)
      q.quote
    end

    def visit!(q : QAccessField)
      head = visit(q.head)

      field(head, q.path) ||
        die(
          "could not follow path '#{q.path.join(".")}' " \
          "given this value: #{head}")
    end

    def visit!(q : QBinarySpread)
      operand = visit(q.operand)

      if !operand.is_a?(Vec)
        die("could not spread over this value: #{operand}")
      elsif operand.value.empty?
        return operand
      elsif operand.value.size == 1
        return operand.value.first
      end

      # Apply the operation on two first items to induce
      # the type of the accumulator:
      memo = binary(q.operator, operand.value.first, operand.value[1])

      operand.value[2...].reduce(memo) do |acc, item|
        binary(q.operator, acc, item)
      end
    end

    def visit!(q : QLambdaSpread)
      operand = visit(q.operand)

      if !operand.is_a?(Vec)
        die("could not spread over this value: #{operand}")
      elsif operand.value.empty?
        return operand
      end

      result = Models.new

      @context.in do
        operand.value.each_with_index do |item, index|
          @context.with_u([Num.new(index), item]) do
            this = visit(q.lambda)

            # Iterative spreads do not map (what we're doing
            # below is essentially mapping).
            next if q.iterative

            unless this.is_a?(MBool) && !this.value
              result << this
            end
          end
        end
      end

      q.iterative ? operand : Vec.new(result)
    end

    def visit!(q : QIf)
      condition = visit(q.cond)

      @context.with_u([condition]) do
        suc, alt = q.suc, q.alt

        if condition.truth?
          visit(suc)
        elsif alt
          visit(alt)
        else
          B_FALSE
        end
      end
    end

    def visit!(q : QBlock)
      visit(q.body).last? || die("cannot evaluate an empty block")
    end

    def visit!(q : QAssign)
      @context.define(q.target, visit(q.value), local: q.local)
    end

    def visit!(q : QBinaryAssign)
      previous = fetch(q.target)

      # We need two copies of the operand value: one we'll work
      # with ourselves, the other we'll give back to the user.
      original = visit(q.value)
      working = original.dup

      # We **wrap** *working* in a vector, not convert. E.g.,
      #   x = [1, 2];
      #   x &= [3]; #) wraps
      #   ensure x is [1, 2, [3]];
      #   y = [1, 2];
      #   y = y & [3]; #) converts
      #   ensure y is [1, 2, 3];
      working = Vec.new([working]) if q.operator == "&"

      # XXX: binary assignment is never local (?)
      @context.define(q.target, binary(q.operator, previous, working), local: false)

      original
    end

    def visit!(q : QFun)
      constraints = constrained(q.params, by: q.given)

      this = MConcreteFunction.new(
        q.tag,
        q.name,
        constraints,
        q.body,
        q.slurpy)

      # Try to find an existing function, generic or concrete.
      # If found a generic function, add *this* function as one
      # of its implementations. If found a concrete function,
      # create a generic that can hold both the found function
      # and *this* function. If found nothing, store *this* as
      # a concrete function.
      existing = @context.fetch(q.name)

      case existing
      when MGenericFunction
        existing.add(this)
      when MConcreteFunction
        if existing != this
          generic = MGenericFunction.new(q.name)

          generic.add(existing)
          generic.add(this)
        end

        @context.define(q.name, generic ||= this)
      else
        @context.define(q.name, this)
      end
    end

    def visit!(q : QEnsure)
      value = visit(q.expression)

      unless value.truth?
        die("'ensure' got a falsey value")
      end

      value
    end

    def visit!(q : QCall)
      head : Model? = nil
      args = visit(q.args)

      if (access = q.callee).is_a?(QAccessField)
        head = visit(access.head)

        # Try to `field` until a field is **not** found
        access.path.each_with_index do |route, index|
          unless value = field(head, route)
            # *route* is not a field. But we must make sure
            # it is a single field accessor.
            unless route.is_a?(SingleFieldAccessor)
              die(
                "attempt to resolve a dynamic field on " \
                "a value that does not exist")
            end

            route = route.field

            # Try searching for a symbol called *route*.
            callee = @context.fetch(route)

            unless callee && callee.callable?
              die(
                "could neither get the field '#{route}' nor " \
                "find a callable named '#{route}' for this value: #{head}")
            end

            if access.path.size == index + 1
              # Here, we're on the last path member:
              #   a.b.c(1).d(1, 2, 3)
              #   ^^^^^^^^ ^ ^^^^^^^
              #   [||||||] | [|||||]
              #     head   |   args
              #          callee
              args.unshift(head)

              break head = callee
            else
              @context.tracing({q.tag, callee.to_s}) do
                value = call(callee, [head])
              end
            end
          end

          head = value.as(Model)
        end
      end

      head ||= visit(q.callee)

      unless head.callable?
        die("this callee is not callable: #{head}")
      end

      @context.tracing({q.tag, head.to_s}) do
        call(head, args)
      end
    end

    def visit!(q : QInfiniteLoop)
      loop { visit(q.body) }
    end

    # :nodoc:
    private macro evaluated_body_last?
      last = visit(q.body).last?
    end

    # :nodoc:
    #
    # Boilerplate code for the loops (QBaseLoop, QStepLoop
    # and QComplexLoop) that handle 'next loop's (& bare 'next's).
    private macro loop_body_handler
      begin
        evaluated_body_last?
      rescue interrupt : NextInterrupt
        if interrupt.target.nil? || interrupt.target == "loop"
          interrupt.args.empty? \
            ? next
            : die("no support for 'next loop' arguments yet :(")
        end

        raise interrupt
      end
    end

    def visit!(q : QBaseLoop)
      last = nil

      case base = visit(q.base)
      when Num
        amount = base.value

        unless amount.denominator == 1
          die("cannot iterate non-whole amount of times: #{amount}")
        end

        amount.numerator.times do
          loop_body_handler
        end
      when .truth?
        loop do
          loop_body_handler

          unless visit(q.base).truth?
            break
          end
        end
      end

      may_be last
    end

    def visit!(q : QStepLoop)
      while visit(q.base).truth?
        loop_body_handler

        visit(q.step)
      end

      may_be last
    end

    def visit!(q : QComplexLoop)
      visit(q.start)

      while visit(q.base).truth?
        # Evaluate pres (pre-statements):
        #  loop (a; b; c; d; e) ...
        #  start-^  ^  {^^}  ^
        #     base -+   |    |
        #         pres -+    |
        #              step -+

        visit(q.pres)

        loop_body_handler

        visit(q.step)
      end

      may_be last
    end

    def visit!(q : QModelCarrier)
      q.model
    end

    def visit!(q : QExpose)
      unless @world.expose(q.pieces)
        die("this distinct was not found: '#{q.pieces.join(".")}'")
      end

      B_TRUE
    end

    def visit!(q : QDistinct)
      B_TRUE
    end

    def visit!(q : QNext)
      args = visit(q.args)

      raise NextInterrupt.new(q.scope, args)
    end

    def visit!(q : QBox)
      constraints = constrained(q.params, by: q.given)

      box = MBox.new(q.tag, q.name, constraints, q.namespace)

      @context.define(q.name, box)
    end

    # Resolves a `SingleFieldAccessor` for *head*. Simply an
    # unpack alias for `field(head, field)`;
    def field(head, accessor : SingleFieldAccessor)
      field(head, accessor.field)
    end

    # Resolves a `DynamicFieldAccessor` for *head*. The *field*
    # of the DynamicFieldAccessor must evaluate to `Str`. Symbols
    # are interpreted differently: if a symbol is defined, its
    # value is used as a field's name; if it isn't it itself
    # is used as a field's name:
    #  ```ven
    #  box Foo(a, b);
    #
    #  foo = Foo(3, 4);
    #
    #  #) 'a' is not defined at this point:
    #  ensure foo.(a) is 3;
    #
    #  #) Now it is:
    #  ensure { a = "b"; foo.(a) } is 4;
    #  ```
    def field(head, accessor : DynamicFieldAccessor)
      case field = accessor.field
      when QSymbol # a freestanding symbol
        unless @context.fetch(field.value)
          return field(head, field.value)
        end
      when QAccessField # nested field access
        if (nfa_head = field.head).is_a?(QSymbol)
          if value = field(head, nfa_head.value)
            return field(value, field.path)
          end
        end
      end

      value = visit(accessor.field)

      unless value.is_a?(Str)
        die("field accessor returned this instead of a string: #{value}")
      end

      field(head, value.value)
    end

    # Resolves a `MultiFieldAccessor` for *head*. Returns a
    # `Vec` of the gathered values, or nil if some were not
    # found.
    def field(head, accessor : MultiFieldAccessor)
      values =
        accessor.field.map do |field|
          return unless value = field(head, field); value
        end

      Vec.new(values)
    end

    # Resolves the *route* for *head*.
    def field(head, route : Array(FieldAccessor))
      route.each do |routee|
        break unless head = field(head, routee)
      end

      head
    end

    # Accesses *head*'s field *field*. Returns nil if there
    # is no such field.
    def field(head : Model, field : String) : Model?
      case field
      when "callable?"
        # 'callable?' is available on all models
        to_bool head.callable?
      else
        head.field(field)
      end
    end

    # Typechecks *args* against *constraints* (via `of?`).
    def typecheck(constraints : ConstrainedParameters, args : Models) : Bool
      rest =
        if constraints.last?.try(&.name) == "*"
          constraints.last
        end

      # Rest typecheck semantics differs a bit from the
      # normal constraint checking; we will omit the rest
      # constraint for now, if there ever was one.
      constraints = constraints[...-1] if rest

      constraints.zip(args).each do |constraint, argument|
        unless constraint.matches(argument)
          return false
        end
      end

      return true unless rest

      args[constraints.size...].all? do |this|
        rest.matches(this)
      end
    end

    # Instantiates an `MBox` with arguments *args*.
    def call(callee : MBox, args : Models)
      unless callee.slurpy || args.size == callee.arity
        die("#{callee} did not receive the correct amount of " \
            "arguments (#{callee.arity})")
      end

      unless typecheck(callee.constraints, args)
        die("typecheck failed for #{callee}: #{args.join(", ")}")
      end

      @context.in(callee.params, args) do
        callee.namespace.each do |name, value|
          @context[name] = visit(value)
        end

        if callee.slurpy
          @context["rest"] = Vec.new(args[callee.arity...])
        end

        MBoxInstance.new(callee, @context.scope?)
      end
    end

    # Calls an `MConcreteFunction` with *args*, checking their
    # types if *typecheck* is true. *generic* determines the
    # behavior of 'next': if set to true, 'next' would not be
    # captured.
    def call(callee : MConcreteFunction, args : Models, typecheck = true, generic = false) : Model
      loop do
        begin
          if typecheck
            unless callee.slurpy || callee.arity == args.size
              die("#{callee} did not receive the correct amount of " \
                  "arguments (#{callee.arity})")
            end

            unless typecheck(callee.constraints, args)
              die("typecheck failed for #{callee}: #{args.join(", ")}")
            end
          end

          @context.in(callee.params, args) do
            if @context.traces.size > MAX_CALL_DEPTH
              die("too many calls: very deep or infinite recursion")
            end

            # If this is **not** a slurpy, break out of the loop
            # with the visited body's last expression:
            unless callee.slurpy
              return visit(callee.body).last
            end

            # If this is a slurpy, though, make the 'rest'
            # symbol contain the remaining arguments, push
            # **all** (XXX) arguments to the underscores stack
            # in reverse order and break out of the loop with
            # visited body's last expression.

            @context["rest"] = Vec.new(args[callee.params.size...])

            @context.with_u(args.reverse) do
              return visit(callee.body).last
            end
          end
        end
      rescue interrupt : NextInterrupt
        unless interrupt.target.nil? || interrupt.target == "fun"
          die("#{interrupt} caught by #{callee}")
        end

        unless generic
          next (args = interrupt.args unless interrupt.args.empty?)
        end

        raise interrupt
      end
    end

    # Calls an `MGenericFunction` with *args*.
    def call(callee : MGenericFunction, args) : Model
      loop do
        begin
          # Goes over the variants of *callee* until a *suitable*
          # variant is found & typecheck against constraints passes.
          callee.variants.each do |variant|
            suitable =
              (variant.slurpy && args.size >= variant.arity) ||
              (variant.params.size == args.size)

            if suitable && typecheck(variant.constraints, args)
              return call(variant, args, typecheck: false, generic: true)
            end
          end
        rescue interrupt : NextInterrupt
          unless interrupt.target.nil? || interrupt.target == "fun"
            die("#{interrupt} captured by #{callee}")
          end

          next (args = interrupt.args unless interrupt.args.empty?)
        end

        die("#{callee} could not accept these arguments: #{args.join(", ")}")
      end
    end

    # Calls an `MBuiltinFunction` with *args*.
    def call(callee : MBuiltinFunction, args) : Model
      callee.block.call(self, args)
    end

    # Returns the n-th item of *vector*.
    def call(vector : Vec, args)
      return Vec.new if args.empty?

      items = args.map do |index|
        if !(index.is_a?(Num) && index.value.denominator == 1)
          die("invalid vector index: #{index}")
        elsif !(item = vector.value[index.value.numerator]?)
          die("vector index out of range: #{index}")
        end

        item
      end

      args.size > 1 ? Vec.new(items) : items.first
    end

    # Returns the n-th character of *string*.
    def call(string : Str, args)
      return Str.new("") if args.empty?

      chars = args.map do |index|
        if !(index.is_a?(Num) && index.value.denominator == 1)
          die("invalid string index: #{index}")
        elsif !(char = string.value[index.value.numerator]?)
          die("string index out of range: #{index}")
        end

        Str.new(char.to_s).as(Model)
      end

      args.size > 1 ? Vec.new(chars) : chars.first
    end

    def call(callee : Model, args)
      die("this callee is not callable: #{callee}")
    end

    # Applies unary *operator* to *operand*.
    def unary(operator, operand : Model) : Model
      case operator
      when "+" then operand.to_num
      when "-" then -operand.to_num
      when "~" then operand.to_str
      when "&" then operand.to_vec
      when "not" then operand.to_bool(inverse: true)
      when "#"
        unless operand.is_a?(Vec) || operand.is_a?(Str)
          operand = operand.to_str
        end

        operand.is_a?(Str) \
          ? operand.to_num(parse: false)
          : operand.to_num
      else
        die("could not apply '#{operator}' to #{operand}")
      end
    rescue e : ModelCastException
      die("'#{operator}': cannot normalize #{operand}: #{e.message}")
    end

    # Converts *left* and *right* into the types *operator*
    # can work with.
    def normalize(operator, left : Model, right : Model) : {Model, Model}
      case operator
      when "is" then case {left, right}
        when {_, MBox},
             {_, MBoxInstance}
          {right, left}
        when {Vec, _}
          {left, right.to_vec}
        when {_, Vec}
          {left.to_vec, right}
        when {_, MRegex}
          {left.to_str, right}
        when {Str, _}
          {left, right.to_str}
        when {Num, _}
          {left, right.to_num}
        when {MBool, _}
          {left, right.to_bool}
        when {_, MBool}
          {left.to_bool, right}
        end
      when "<", ">", "<=", ">="
        {left.to_num, right.to_num}
      when "+", "-", "*", "/"
        {left.to_num, right.to_num}
      when "~"
        {left.to_str, right.to_str}
      when "&"
        {left.to_vec, right.to_vec}
      when "x" then case {left, right}
        when {_, Vec}, {_, Str}
          {right, left.to_num}
        when {Vec, _}, {Str, _}
          {left, right.to_num}
        else
          {left.to_vec, right.to_num}
        end
      end || die(
        "'#{operator}': could not normalize these operands: " \
        "#{left}, #{right} (try changing the order)")
    end

    # Computes a binary operation. Returns false if *left*
    # and/or *right* are not of types *operator* can work with.
    def compute(operator, left : Model, right : Model)
      case {operator, left, right}
      when {"and", _, _}
        truthy right, if: !(left.is_bool_false? || right.is_bool_false?)
      when {"or", _, _}
        left.is_bool_false? \
          ? truthy right, if: !right.is_bool_false?
          : truthy left
      when {"is", MBool, MBool},
           {"is", Num, Num},
           {"is", Str, Str},
           {"is", Vec, Vec},
           {"is", MBox, _},
           {"is", MBoxInstance, _}
        truthy left, if: left.eqv?(right)
      when {"is", _, MType}
        to_bool left.of?(right)
      when {"is", Str, MRegex}
        truthy Str.new($0), if: left.value =~ right.value
      when {"in", _, Vec}
        may_be right.value.each { |i| break i if left.eqv?(i) }
      when {"<", Num, Num}
        to_bool left.value < right.value
      when {">", Num, Num}
        to_bool left.value > right.value
      when {"<=", Num, Num}
        to_bool left.value <= right.value
      when {">=", Num, Num}
        to_bool left.value >= right.value
      when {"+", Num, Num}
        Num.new(left.value + right.value)
      when {"-", Num, Num}
        Num.new(left.value - right.value)
      when {"*", Num, Num}
        Num.new(left.value * right.value)
      when {"/", Num, Num}
        Num.new(left.value / right.value)
      when {"~", Str, Str}
        Str.new(left.value + right.value)
      when {"&", Vec, Vec}
        Vec.new(left.value + right.value)
      when {"x", Str, Num}
        Str.new(left.value * right.value.to_big_i)
      when {"x", Vec, Num}
        Vec.new(left.value * right.value.to_big_i)
      else
        false
      end
    rescue DivisionByZeroError
      die("'#{operator}': division by zero: #{left}, #{right}")
    end

    # Applies binary *operator* to *left* and *right*.
    def binary(operator, left : Model, right : Model)
      until result = compute(operator, left, right)
        left, right = normalize(operator, left, right)
      end

      result.as(Model)
    rescue e : ModelCastException
      die("'#{operator}': cannot normalize #{left}, #{right}: #{e.message}")
    end
  end
end
