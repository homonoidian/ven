require "./component/*"

require "big"

module Ven
  class Machine < Component::Visitor
    include Component

    # Maximum call depth (see `call`).
    MAX_CALL_DEPTH = 500

    # Maximum amount of normalization passes (see `normalize`).
    MAX_NORMALIZE_PASSES = 500

    # Ven booleans are structs (copy on use) and need no
    # repetitive `.new`s.
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

    # If *condition* is Crystal true, returns *left*; otherwise,
    # returns Ven boolean false. *condition* may be omitted;
    # in that case, *left* will be used as *condition*.
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

    # Dies of runtime error with *message*. Constructs a
    # traceback where the top entry is the outermost call,
    # and the bottom entry is a unit that was the actual
    # cause of this death (`@last`).
    def die(message : String)
      traces = [message] + @context.traces + [Trace.new(@last.tag, "<unit>")]

      raise RuntimeError.new(@last.tag, traces.join("\n from "))
    end

    def visit!(q : QSymbol)
      unless value = @context.fetch(q.value)
        die("could not find '#{q.value}' in current scope")
      end

      value.as(Model)
    end

    def visit!(q : QNumber)
      Num.new(q.value)
    end

    def visit!(q : QString)
      Str.new(q.value)
    end

    def visit!(q : QRegex)
      # Assume we'll be matching from the start of the string:
      regex = q.value.starts_with?("^") ? q.value : "^#{q.value}"

      MRegex.new(Regex.new(regex), string: q.value)
    rescue ArgumentError
      die("regex syntax error: invalid PCRE literal: #{q}")
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

    def visit!(q : QQuote)
      q.quote
    end

    def visit!(q : QAccessField)
      head = visit(q.head)

      q.path.each do |route|
        value = field(head, route)

        unless value
          die("field '#{route}' not found for this value: #{head}")
        end

        head = value.as(Model)
      end

      head
    end

    def visit!(q : QBinarySpread)
      body = visit(q.body)

      if !body.is_a?(Vec)
        die("could not spread on this value: #{body}")
      elsif body.value.size == 0
        return body
      elsif body.value.size == 1
        return body.value.first
      end

      # Apply the operation on two first items to induce
      # the type of the accumulator
      memo = binary(q.operator, body.value.first, body.value[1])

      body.value[2...].reduce(memo) do |acc, item|
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

      item = operand.value.first
      result = [] of Model

      @context.tracing({q.tag, "<spread>"}) do
        @context.local do
          operand.value.each_with_index do |item, index|
            @context.with_u([Num.new(index), item]) do
              factor = visit(q.lambda)

              unless q.iterative
                if factor.is_a?(MBool)
                  factor = (factor.value ? item : next)
                end

                result << factor
              end
            end
          end
        end
      end

      result.empty? ? operand : Vec.new(result)
    end

    def visit!(q : QIf)
      condition = visit(q.cond)

      @context.with_u([condition]) do
        suc, alt = q.suc, q.alt

        if condition.true?
          visit(suc)
        elsif alt
          visit(alt)
        else
          B_FALSE
        end
      end
    end

    def visit!(q : QBlock)
      may_be visit(q.body).last?
    end

    def visit!(q : QAssign)
      @context.define(q.target, visit(q.value))
    end

    def visit!(q : QBinaryAssign)
      unless previous = @context.fetch(q.target)
        die("this assignment is illegal: '#{q.target}' was never declared")
      end

      # We need two copies of the given value: one we'll work
      # with, and one the user expects to be returned.
      given = visit(q.value)
      value = given.dup

      # We **wrap** *value* into a vector, not convert. E.g.,
      #   x = [1, 2];
      #   x &= [3];
      #   ensure x is [1, 2, [3]];
      #   y = [1, 2];
      #   y = y & [3];
      #   ensure y is [1, 2, 3];
      value = Vec.new([value]) if q.operator == "&"

      result = binary(q.operator, previous, value)
      @context.define(q.target, result)

      given
    end

    def visit!(q : QFun)
      # Evaluate the 'given' expressions, making sure that
      # each returns a type. If the type was not specified
      # for a parameter, make it MType::ANY.
      last = MType::ANY

      params = q.params.zip?(q.given).map do |param, type|
        if !type.nil? && !(last = visit(type)).is_a?(MType)
          die("this 'given' expression did not return a type: #{type}")
        end

        {param, last.as(MType)}
      end

      this = MConcreteFunction.new(
        q.tag,
        q.name,
        params,
        q.body,
        q.slurpy)

      # Try to find an existing function, generic or concrete.
      # If found a generic function, add this function as one
      # of its implementations. If found a concrete function,
      # create a generic that can hold both the found function
      # and this one. If found nothing, store this concrete
      # function under the name it has.
      existing = @context.fetch(q.name)

      case existing
      when MGenericFunction
        existing.add(this)
      when MConcreteFunction
        generic = MGenericFunction.new(q.name)

        generic.add(existing)
        generic.add(this)

        @context.define(q.name, generic)
      else
        @context.define(q.name, this)
      end
    end

    def visit!(q : QEnsure)
      unless (value = visit(q.expression)).true?
        die("failed to ensure: #{value}")
      end

      value
    end

    def visit!(q : QCall)
      head : Model? = nil
      args = visit(q.args)

      if (access = q.callee).is_a?(QAccessField)
        head = visit(access.head)

        # Try to `field` until a field is not found
        access.path.each_with_index do |route, index|
          unless value = field(head, route)
            # *route* is not a field. Try making a call to a
            # variable named *route*, whose value will be the
            # callee and *head* the only argument.
            callee = @context.fetch(route)

            unless callee && callee.callable?
              die(
                "could neither get the field '#{route}' nor " \
                "find a callable named '#{route}' for this value: #{head}")
            end

            if access.path.size == index + 1
              # We're going for the normies' call!
              args.unshift(head)

              break head = callee
            else
              @context.tracing({q.tag, "<call to #{route}>"}) do
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

      @context.tracing({q.tag, "<call to #{head}>"}) do
        call(head, args)
      end
    end

    def visit!(q : QQueue)
      unless @context.has_queue?
        die("use of 'queue' when no queue available")
      end

      @context.queue(visit(q.value))
    end

    def visit!(q : QInfiniteLoop)
      loop do
        visit(q.body)
      end
    end

    def visit!(q : QBaseLoop)
      if q.base.is_a?(QNumber)
        amount = visit(q.base).as(Num).value

        unless amount.denominator == 1
          die("cannot iterate non-whole amount of times: #{amount}")
        end

        amount.numerator.times do
          last = visit(q.body)
        end
      else
        while visit(q.base).true?
          last = visit(q.body).last?
        end
      end

      may_be last
    end

    def visit!(q : QStepLoop)
      while visit(q.base).true?
        last = visit(q.body).last?
        visit(q.step)
      end

      may_be last
    end

    def visit!(q : QComplexLoop)
      visit(q.start)

      while visit(q.base).true?
        visit(q.pres)

        last = visit(q.body).last?

        visit(q.step)
      end

      may_be last
    end

    def visit!(q : QModelCarrier)
      q.model
    end

    def visit!(q : QExpose)
      unless @world.gather(q.pieces)
        die("this distinct was not found: '#{q.pieces.join(".")}'")
      end

      B_TRUE
    end

    def visit!(q : QDistinct)
      B_TRUE
    end

    # Checks if *left* has type *right*.
    def of?(left : Model, right : MType) : Bool
      return true if right.type == MAny

      right.type.is_a?(MClass.class) \
        ? left.class <= right.type.as(MClass.class)
        : left.class <= right.type.as(MStruct.class)
    end

    # Accesses *head*'s field *field*. Returns nil if there
    # is no such field.
    def field(head : Model, field : String)
      case field
      when "callable?"
        # 'callable?' is available on all models
        to_bool head.callable?
      else
        head.field(field)
      end
    end

    # Typechecks *args* against *constraints* (using `of?`).
    def typecheck(constraints : Array(TypedParameter), args : Models) : Bool
      rest_type =
        if constraints.last?.try(&.[0]) == "*"
          constraints.last[1]
        end

      # Rest typecheck semantics differs a bit from normal
      # constraint checking; omit the rest constraint.
      constraints = constraints[...-1] if rest_type

      constraints.zip?(args).each do |constraint, argument|
        # Ignore missing arguments.
        unless argument.nil? || of?(argument, constraint[1])
          return false
        end
      end

      # Rest typecheck:
      if rest_type
        return args[constraints.size...].all? do |argument|
          of?(argument, rest_type)
        end
      end

      true
    end

    # Calls an `MConcreteFunction` with *args*, checking the
    # types if *typecheck* is true.
    def call(callee : MConcreteFunction, args : Models, typecheck = true) : Model
      if typecheck
        unless callee.slurpy || callee.arity == args.size
          die("#{callee} expected #{callee.arity} argument(s), got #{args.size}")
        end

        unless typecheck(callee.constraints, args)
          die("typecheck failed for #{callee}: #{args.join(", ")}")
        end
      end

      @context.local({callee.params, args}) do
        if @context.traces.size > MAX_CALL_DEPTH
          die("too many calls: very deep or infinite recursion")
        end

        unless callee.slurpy
          return visit(callee.body).last
        end

        @context.scope["rest"] = Vec.new(args[callee.params.size...])

        @context.with_u(args.reverse) do
          visit(callee.body).last
        end
      end
    end

    # Calls an `MGenericFunction` with *args*.
    def call(callee : MGenericFunction, args) : Model
      callee.variants.each do |variant|
        if (variant.slurpy && args.size >= variant.arity) || variant.params.size == args.size
          if typecheck(variant.constraints, args)
            return call(variant, args, typecheck: false)
          end
        end
      end

      die("no concrete of #{callee} could receive these arguments: #{args.join(", ")}")
    end

    # Calls an `MBuiltinFunction` with *args*.
    def call(callee : MBuiltinFunction, args) : Model
      callee.block.call(self, args)
    end

    # Returns the n-th item of *vector*.
    def call(vector : Vec, args)
      return Vec.new if args.empty?

      items = args.map do |index|
        if !(index.is_a?(MNumber) && index.value.denominator == 1)
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
        if !(index.is_a?(MNumber) && index.value.denominator == 1)
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

    # Returns whether *left* and *right* can be used with
    # *operator*.
    def compatible?(operator, left : Model, right : Model) : Bool
      case {operator, left, right}
      when {"is", Vec, Vec}
      when {"is", MBool, MBool}
      when {"is", Str, MRegex}
      when {"is", _, MType}
      when {"in", _, Vec}
      when {"is", Num, Num},
           {"<", Num, Num},
           {">", Num, Num},
           {"<=", Num, Num},
           {">=", Num, Num}
      when {"+", Num, Num},
           {"-", Num, Num},
           {"*", Num, Num},
           {"/", Num, Num}
      when {"is", Str, Str},
           {"~", Str, Str},
           {"x", Str, Num}
      when {"&", Vec, Vec},
           {"x", Vec, Num}
      else
        return false # i.e., incompatible
      end

      true
    end

    # Converts *left* and *right* into the types *operator*
    # expects (i.e.,  `compatible?`).
    def normalize(operator, left : Model, right : Model) : {Model, Model}
      case operator
      when "is" then case {left, right}
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
      when "+", "-", "*", "/" then case {left, right}
        when {_, Num}
          {left.to_num, right}
        when {Num, _}
          {left, right.to_num}
        else
          {left.to_num, right.to_num}
        end
      when "~" then case {left, right}
        when {_, Str}
          {left.to_str, right}
        when {Str, _}
          {left, right.to_str}
        else
          {left.to_str, right.to_str}
        end
      when "&" then case {left, right}
        when {_, Vec}
          {left.to_vec, right}
        when {Vec, _}
          {left, right.to_vec}
        else
          {left.to_vec, right.to_vec}
        end
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

    # Checks whether *left* and  *right* are equal by value (not
    # semantically). E.g., while `0 is false` (semantic equality)
    # yields true, `0 <eqv> false` yields false.
    # NOTE: `eqv` is not available inside the language itself.
    def eqv?(left, right)
      false
    end

    # See `eqv?(left, right)`.
    def eqv?(left : Num | Str | MBool, right : Num | Str | MBool)
      left.value == right.value
    end

    # See `eqv?(left, right)`.
    def eqv?(left : Vec, right : Vec)
      lv, rv = left.value, right.value

      lv.size == rv.size && lv.zip(rv).all? { |li, ri| eqv?(li, ri) }
    end

    # Computes a binary operation. This is the third (and the
    # last) step of binary operator evaluation, and it requires
    # *left* and *right* be **normalized**.
    def compute(operator, left : Model, right : Model) : Model
      left =
        case {operator, left, right}
        when {"is", MBool, MBool},
             {"is", Num, Num},
             {"is", Str, Str},
             {"is", Vec, Vec}
          may_be left, if: eqv?(left, right)
        when {"is", _, MType}
          to_bool of?(left, right)
        when {"is", Str, MRegex}
          may_be Str.new($0), if: left.value =~ right.value
        when {"in", _, Vec}
          it = right.value.each { |i| break i if eqv?(left, i) }

          may_be it
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
          die("could not apply '#{operator}' to #{left}, #{right}")
        end

      left
    rescue DivisionByZeroError
      die("'#{operator}': division by zero: #{left}, #{right}")
    end

    # Applies binary *operator* to *left* and *right*.
    def binary(operator, left : Model, right : Model) : Model
      passes = 0

      # Perform normalization passes until *operator* is
      # compatible with *left*, *right*.
      until compatible?(operator, left, right)
        if (passes += 1) > MAX_NORMALIZE_PASSES
          raise InternalError.new(
              "too many normalization passes; you've probably " \
              "found an implementation bug, as '#{operator}' " \
              "requested normalization more than " \
              "#{MAX_NORMALIZE_PASSES} times")
        end

        left, right = normalize(operator, left, right)
      end

      compute(operator, left, right)
    rescue e : ModelCastException
      die("'#{operator}': cannot normalize #{left}, #{right}: #{e.message}")
    end

    # Evaluates the *tree* within the *context*. `clear`s this
    # context beforehand.
    def self.run(tree : Quotes, context : Context)
      new(context.clear).visit(tree)
    end
  end
end
