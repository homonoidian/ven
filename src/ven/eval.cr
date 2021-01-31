require "./component/*"

require "big"

module Ven
  class Machine < Component::Visitor
    include Component

    # Maximum depth of calls (see `call`).
    MAX_CALL_DEPTH = 500

    # Maximum amount of normalization passes (see `normalize!`).
    MAX_NORMALIZE_PASSES = 500

    # Maximum amount of compute cycles (see `compute`).
    MAX_COMPUTE_CYCLES = 1000

    # Ven booleans are structs (copy on use) and need no
    # explicit `.new`.
    B_TRUE = MBool.new(true)
    B_FALSE = MBool.new(false)

    def initialize(@context = Context.new)
      @computes = 0
    end

    ### Error handling

    def die(message : String)
      raise InternalError.new("no last node") if @last.nil?

      # Construct the traceback in a clever (?) way
      last = @last.not_nil!
      trace = Trace.new(last.tag, "<unit>")
      message = ([message] + @context.traces + [trace]).join("\n  from ")

      raise RuntimeError.new(last.tag, message)
    end

    ### Top-level visitors

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
      false?(visit(q.value)) ? B_FALSE : B_TRUE
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
      cond = visit(q.cond)

      # XXX: controversial, e.g., `if (0) 1` yields `1` (1)
      branch = cond.is_a?(MBool) && !cond.value ? q.alt : q.suc

      branch.nil? \
        ? B_FALSE
        : @context.with_u([cond]) { visit(branch) }
    end

    def visit!(q : QBlock)
      visit(q.body).last? || B_FALSE
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
      value = given

      # If we're `~=`, the semantics is a little different than
      # with <left> = <left> ~ <value>.
      if q.operator == "~"
        # We *wrap* anything given into a vector, not convert.
        value = Vec.new([value])
      end

      result = binary(q.operator, previous, value)

      @context.define(q.target, result)

      # XXX: is this what users expect?
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
      if false?(value = visit(q.expression))
        die("#{value} is false (ensuring: #{q.expression})")
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

      @context.tracing({q.tag, "<call to #{head}>"}) do
        call(head, args)
      end
    end

    def visit!(q : QQueue)
      die("use of 'queue' when no queue available") unless @context.has_queue?

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
        while true? visit(q.base)
          last = visit(q.body).last?
        end
      end

      last ||= B_FALSE
    end

    def visit!(q : QStepLoop)
      while true? visit(q.base)
        last = visit(q.body).last?
        visit(q.step)
      end

      last ||= B_FALSE
    end

    def visit!(q : QComplexLoop)
      visit(q.start)

      while true? visit(q.base)
        visit(q.pres)

        last = visit(q.body).last?

        visit(q.step)
      end

      last ||= B_FALSE
    end

    ### Helpers

    # Checks whether, according to Ven, the *model* is false.
    def false?(model : Model) : Bool
      case model
      when Vec
        model.value.each do |item|
          if false?(item)
            return true
          end
        end

        false
      when Str
        model.value.empty?
      when Num
        model.value == 0
      when MBool
        !model.value
      else
        false
      end
    end

    # Checks if *left* is of the type *right*.
    def of?(left : Model, right : MType) : Bool
      return true if right.type == MAny

      right.type.is_a?(MClass.class) \
        ? left.class <= right.type.as(MClass.class)
        : left.class <= right.type.as(MStruct.class)
    end

    # Returns an inverse of `false?`.
    private macro true?(model)
      !false?({{model}})
    end

    # Converts a Crystal boolean into a Ven boolean.
    private macro to_bool(bool)
      {{bool}} ? B_TRUE : B_FALSE
    end

    # Converts a Model into a Ven boolean.
    private macro as_bool(model)
      true?({{model}}) ? B_TRUE : B_FALSE
    end

    ### Fields

    # Accesses *head*'s *field*. Returns nil if such field
    # was not found.
    def field(head : Model, field : String) : Model?
      if result = head.field(field)
        return result.as(Model)
      end

      case field
      when "callable?"
        # 'callable?' is available anytime, on any model
        to_bool(head.callable?)
      end
    end

    ### Calls

    private def typecheck(params : Array(TypedParameter), args : Models) : Bool
      params.zip?(args).each do |param, arg|
        # Ignore missing arguments
        unless arg.nil? || of?(arg, param[1])
          return false
        end
      end

      true
    end

    # Interprets a call to an `MConcreteFunction`.
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
        # $QUEUE is an internal variable; those are variables
        # that could only be used/created by the interpreter
        @context.scope["$QUEUE"] = Vec.new([] of Model)

        if callee.slurpy
          @context.scope["rest"] = Vec.new(args[callee.params.size...])
        end

        # @context.with_u(args.reverse) do
          if @context.traces.size > MAX_CALL_DEPTH
            die("too many calls: very deep or infinite recursion")
          end

          result = visit(callee.body)
          queue = @context.scope["$QUEUE"].as(Vec)

          queue.value.empty? ? result.last : queue
        # end
      end
    end

    # Interprets a call to an `MGenericFunction`.
    def call(callee : MGenericFunction, args) : Model
      callee.variants.each do |variant|
        if variant.slurpy && variant.arity <= args.size
          # It's a slurpy. Stretch the constraints (by repeating
          # last mentioned constraint) so they fit args and
          # 'typecheck' can do its work
          constraints = variant.constraints

          (args.size - constraints.size).times do
            constraints << constraints.last
          end

          if typecheck(constraints, args)
            return call(variant, args, typecheck: false)
          end
        elsif variant.params.size == args.size
          # A non-slurpy variant. Just typecheck it and,
          # if the typecheck was successful, run it.
          if typecheck(variant.constraints, args)
            return call(variant, args, typecheck: false)
          end
        end
      end

      die("no concrete of #{callee} could receive these arguments: #{args.join(", ")}")
    end

    # Interprets a call to an `MBuiltinFunction`.
    def call(callee : MBuiltinFunction, args) : Model
      callee.block.call(self, args)
    end

    # Interprets a call to an `MVector`.
    def call(callee : Vec, args) : Model
      return Vec.new([] of Model) if args.empty?

      result = args.map do |arg|
        if !arg.is_a?(MNumber)
          die("vector index must be a num, got: #{arg}")
        elsif !arg.value.denominator == 1
          die("vector index must be a whole num, got rational: #{arg}")
        elsif (item = callee.value[arg.value.numerator]?).nil?
          die("vector has no item with index #{arg}")
        end
        item
      end

      args.size > 1 ? Vec.new(result) : result.first
    end

    def call(callee : Model, args)
      die("could not call this callee: #{callee}")
    end

    ### Unary (prefix) operations

    # Interprets a unary operation.
    def unary(operator, operand : Model) : Model
      case operator
      when "+"
        operand.is_a?(Str) \
          ? operand.to_num(parse: true)
          : operand.to_num
      when "-"
        numeric = operand.is_a?(Str) \
          ? operand.to_num(parse: true)
          : operand.to_num

        numeric.value = -numeric.value
        numeric
      when "~"
        operand.to_str
      when "not"
        false?(operand) ? B_TRUE : B_FALSE
      else
        die("'#{operator}': could not interpret for this operand: #{operand}")
      end
    rescue e : ModelCastException
      die("'#{operator}': cannot cast (to normalize) #{operand}: #{e.message}")
    end

    ### Binary operations

    # Returns whether *left* and *right* need a normalization
    # pass to be used with *operator*.
    def normalize?(operator, left : Model, right : Model) : Bool
      case {operator, left, right}
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
      when {"~", Vec, Vec},
           {"x", Vec, Num}
      when {_, Vec, Vec}
        # Other vector operations are distributed on vector items;
        # so there is no need nor support for their normalization
      else
        return true
      end

      false
    end

    # Returns a tuple `{left, right}` where left, right are
    # **normalized** *left*, *right*.
    def normalize!(operator, left : Model, right : Model) : {Model, Model}
      case operator
      when "is" then case {left, right}
        when {Vec, _}, {_, Vec}
          {left.to_vec, right.to_vec}
        when {_, MRegex}
          {left.to_str, right}
        when {Str, _}
          {left, right.to_str}
        when {Num, _}
          {left, right.to_num}
        when {MBool, _}, {_, MBool}
          {as_bool(left), as_bool(right)}
        end
      when "<", ">", "<=", ">=" then case {left, right}
        when {Vec, _}
          {left, right.to_vec}
        else
          {left.to_num, right.to_num}
        end
      when "+", "-", "*", "/" then case {left, right}
        when {Vec, _}, {_, Vec}
          {left.to_vec, right.to_vec}
        else
          {left.to_num, right.to_num}
        end
      when "~" then case {left, right}
        when {Vec, _}, {_, Vec}
          {left.to_vec, right.to_vec}
        when {Str, _}, {_, Str}
          {left.to_str, right.to_str}
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

    # Computes a binary operation.
    def compute(operator, left : Model, right : Model) : Model
      if (@computes += 1) > MAX_COMPUTE_CYCLES
        die("too many compute cycles; you've probably found " \
            "an implementation bug: normalizing this operator " \
            "('#{operator}') causes an infinite loop")
      end

      left =
        case {operator, left, right}
        when {"is", Num, Num}
          left.value == right.value ? left : B_FALSE
        when {"is", Str, Str}
          left.value == right.value ? left : B_FALSE
        when {"is", MBool, MBool}
          to_bool(left.value == right.value)
        when {"is", Str, MRegex}
          if match = right.value.match(left.value)
            Vec.new(match.to_a.map { |c| Str.new(c || "").as(Model) })
          else
            B_FALSE
          end
        when {"is", _, MType}
          to_bool(of?(left, right))
        when {"in", _, Vec}
          right.value.each do |item|
            if true?(result = binary("is", left, item))
              break result
            end
          end || B_FALSE
        when {"<", Num, Num}
          to_bool(left.value < right.value)
        when {">", Num, Num}
          to_bool(left.value > right.value)
        when {"<=", Num, Num}
          to_bool(left.value <= right.value)
        when {">=", Num, Num}
          to_bool(left.value >= right.value)
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
        when {"x", Str, Num}
          Str.new(left.value * right.value.to_big_i)
        when {"~", Vec, Vec}
          Vec.new(left.value + right.value)
        when {"x", Vec, Num}
          Vec.new(left.value * right.value.to_big_i)
        when {_, Vec, Vec}
          if right.value.empty?
           right
          else
            result =
              # NOTE: if there are not enough items in *right* to
              # cover *left*, the last item of *right* will be
              # used for this.
              left.value.zip?(right.value).map do |a, b|
                binary(operator, a, b || right.value.last).as(Model)
              end

            Vec.new(result)
          end
        else
          die("'#{operator}': could not interpret these arguments: #{left}, #{right}")
        end

      @computes -= 1

      left
    rescue DivisionByZeroError
      die("'#{operator}': division by zero: #{left}, #{right}")
    end

    # Interprets a binary operation.
    def binary(operator, left : Model, right : Model) : Model
      passes = 0

      # Normalize until satisfied
      while normalize?(operator, left, right)
        if (passes += 1) > MAX_NORMALIZE_PASSES
          die("too many normalization passes; you've probably " \
              "found an implementation bug, as '#{operator}' " \
              "requested normalization  more than " \
              "#{MAX_NORMALIZE_PASSES} times")
        end

        left, right = normalize!(operator, left, right)
      end

      compute(operator, left, right)
    rescue e : ModelCastException
      die("'#{operator}': cannot cast (to normalize): #{left}, #{right}: #{e.message}")
    end

    ### Interaction with the outside world

    # Evaluates *tree* within the given *context*. Clears this
    # context beforehand.
    def self.run(tree : Quotes, context : Context)
      new(context.clear).visit(tree)
    end
  end
end
