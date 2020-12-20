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
      Num.new(q.value.to_big_d)
    end

    def visit!(q : QString)
      Str.new(q.value)
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
      MBool.new(!false?(visit(q.value)))
    end

    def visit!(q : QAccessField)
      head = visit(q.head)

      q.path.each do |unit|
        head = field(head, unit)
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

      result = [] of Model
      item = operand.value.first

      @context.tracing({q.tag, "<spread>"}) do
        @context.local do
          operand.value.each_with_index do |item, index|
            @context.with_u([Num.new(index), item]) do
              factor = visit(q.lambda)
              case factor
              when MHole
                next
              when MBool
                factor = (factor.value ? item : next)
              end
              result << factor
            end
          end
        end
      end

      Vec.new(result)
    end

    def visit!(q : QIf)
      branch = false?(value = visit(q.cond)) ? q.alt : q.suc

      branch.nil? \
        ? MHole.new
        : @context.with_u([value]) { visit(branch) }
    end

    def visit!(q : QBlock)
      visit(q.body).last
    end

    def visit!(q : QAssign)
      @context.define(q.target, visit(q.value))
    end

    def visit!(q : QFun)
      # Evaluate the 'given' expressions, making sure that
      # each returns a type (TODO: or a model). If the type
      # for a parameter is missing, let it be 'any'.
      last = MType.new("any", Model)

      params = q.params.zip?(q.given).map do |param, type|
        if !type.nil? && !(last = visit(type)).is_a?(MType)
          die("this 'given' expression did not return a type: #{type}")
        end

        {param, last.as(MType)}
      end

      concrete = MConcreteFunction.new(
        q.tag,
        q.name,
        params,
        q.body,
        q.slurpy)

      # Search for a generic that handles this function
      # (essentially, a generic named the same way). Create
      # one if haven't found.
      generic = @context.fetch(q.name)

      unless generic.is_a?(MGenericFunction)
        generic = @context.define(q.name, MGenericFunction.new(q.name))
      end

      generic.add(concrete)
    end

    def visit!(q : QEnsure)
      if false?(value = visit(q.expression))
        die("#{value} is false (ensuring: #{q.expression})")
      end

      value
    end

    def visit!(q : QCall)
      callee, args = visit(q.callee), visit(q.args)

      @context.tracing({q.tag, "<call to #{callee}>"}) do
        call(callee, args)
      end
    end

    ### Helpers

    # Checks if *model* is false (according to Ven).
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
      right.type == Model ? true : left.class <= right.type
    end

    # Returns an inverse of `false?`.
    private macro true?(model)
      !false?({{model}})
    end

    # Calls `true?(model)` and makes the result an `MBool`.
    private macro to_bool(model)
      MBool.new(true?({{model}}))
    end

    ### Fields

    # Accesses *head*'s field.
    def field(head : Model, field : String)
      unless result = head.field(field)
        die("field '#{field}' not found for this value: #{head}")
      end

      result.as(Model)
    end

    def field!(head : MConcreteFunction, field : String)
      case field
      when "name"
        Str.new(head.name)
      when "params"
        Vec.new(head.params.map { |param| Str.new(param).as(Model) })
      when "body"
        die("TODO: MQuote")
      end
    end

    def field!(head : MGenericFunction, field : String)
      case field
      when "name"
        Str.new(head.name)
      when "concretes"
        Vec.new(head.concretes.map(&.as(Model)))
      end
    end

    ### Calls

    private def typecheck(params : Array(TypedParameter), args : Array(Model))
      params.zip?(args).each do |param, arg|
        # Ignore missing arguments
        unless !arg.nil? && of?(arg, param[1])
          return false
        end
      end

      true
    end

    # Interprets a call to an `MConcreteFunction`.
    def call(callee : MConcreteFunction, args : Array(Model), typecheck = true)
      if typecheck && !typecheck(callee.constraints, args)
        # TODO: better error
        die("typecheck failed")
      end

      @context.local({callee.params, args}) do
        if callee.slurpy
          @context.define("rest", Vec.new(args[callee.params.size...]))
        end

        @context.with_u(args.reverse) do
          if @context.traces.size > MAX_CALL_DEPTH
            die("too many calls: very deep or infinite recursion")
          elsif (result = visit(callee.body).last).is_a?(MHole)
            die("illegal operation: #{callee} returned a hole")
          else
            result
          end
        end
      end
    end

    # Interprets a call to an `MGenericFunction`.
    def call(callee : MGenericFunction, args)
      callee.concretes.each do |concrete|
        if concrete.slurpy && concrete.params.size <= args.size
          # It's a slurpy. Stretch the constraints (by repeating
          # last mentioned constraint) so they fit args and
          # 'typecheck' can do its work
          constraints = concrete.constraints

          (constraints.size - args.size).times do
            constraints << constraints.last
          end

          if typecheck(constraints, args)
            return call(concrete, args, typecheck: false)
          end
        elsif concrete.params.size == args.size
          # A non-slurpy concrete. Just typecheck it and,
          # if the typecheck was successful, run it.
          if typecheck(concrete.constraints, args)
            return call(concrete, args, typecheck: false)
          end
        end
      end

      die("no concrete of #{callee} could receive these arguments: #{args.join(", ")}")
    end

    # Interprets a call to an `MBuiltinFunction`.
    def call(callee : MBuiltinFunction, args)
      callee.block.call(self, args)
    end

    # Interprets a call to an `MVector` (XXX: will be removed soon)
    def call(callee : Vec, args)
      items = args.map! do |arg|
        if !arg.is_a?(MNumber)
          die("vector index must be a num, got: #{arg}")
        elsif !arg.value.denominator == 1
          die("vector index must be a whole num, got rational: #{arg}")
        elsif (item = callee.value[arg.value.numerator]?).nil?
          die("vector has no item with index #{arg}")
        end
        item
      end

      items.size > 1 ? Vec.new(items) : items.first
    end

    def call(callee : Model, args)
      die("could not call this callee: #{callee}")
    end

    ### Unary (prefix) operations

    # Interprets a unary operation.
    def unary(operator, operand : Model)
      case operator
      when "+"
        operand.to_num
      when "-"
        numeric = operand.to_num
        numeric.value = -numeric.value
        numeric
      when "~"
        operand.to_str
      else
        die("'#{operator}': could not interpret for this operand: #{operand}")
      end
    rescue e : ModelCastException
      die("'#{operator}': cannot cast (to normalize) #{operand}: #{e.message}")
    end

    ### Binary operations

    # Returns true if *left* and *right* need a `normalize!`
    # pass to be used with *operator*.
    def normalize?(operator, left : Model, right : Model)
      case {operator, left, right}
      when {"is", MBool, MBool}
      when {"is", _, MType}
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
        true
      end
    end

    # Returns a tuple `{left, right}` where left, right are
    # **normalized** *left*, *right*.
    def normalize!(operator, left : Model, right : Model)
      case operator
      when "is" then case {left, right}
        when {Vec, _}, {_, Vec}
          {left.to_vec, right.to_vec}
        when {Str, _}, {_, Str}
          {left.to_str, right.to_str}
        when {Num, _}, {_, Num}
          {left.to_num, right.to_num}
        when {MBool, _}, {_, MBool}
          {to_bool(left), to_bool(right)}
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
      end || die("'#{operator}': could not normalize these operands: #{left}, #{right}")
    end

    # Computes a binary operation.
    def compute(operator, left : Model, right : Model)
      if (@computes += 1) > MAX_COMPUTE_CYCLES
        die("too many compute cycles; you've probably found " \
            "an implementation bug: normalizing this operator " \
            "('#{operator}') causes an infinite loop")
      end

      # `left` is going to be changed soon. Copy so we're
      # not modifying its original value
      left = left.dup

      case {operator, left, right}
      when {"is", Num, Num}
        left = left.value == right.value ? left : MBool.new(false)
      when {"is", Str, Str}
        left = left.value == right.value ? left : MBool.new(false)
      when {"is", MBool, MBool}
        left.value = left.value == right.value
      when {"is", _, MType}
        left = MBool.new(of?(left, right))
      when {"<", Num, Num}
        left = MBool.new(left.value < right.value)
      when {">", Num, Num}
        left = MBool.new(left.value > right.value)
      when {"<=", Num, Num}
        left = MBool.new(left.value <= right.value)
      when {">=", Num, Num}
        left = MBool.new(left.value >= right.value)
      when {"+", Num, Num}
        left.value += right.value
      when {"-", Num, Num}
        left.value -= right.value
      when {"*", Num, Num}
        left.value *= right.value
      when {"/", Num, Num}
        left.value /= right.value
      when {"~", Str, Str}
        left.value += right.value
      when {"x", Str, Num}
        left.value *= right.value.to_big_i
      when {"~", Vec, Vec}
        left.value += right.value
      when {"x", Vec, Num}
        left.value *= right.value.to_big_i
      when {_, Vec, Vec}
        return right if right.value.empty?

        left.value = left.value.zip?(right.value).map do |a, b|
          binary(operator, a, b || right.value.last).as(Model)
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
    def binary(operator, left : Model, right : Model)
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
