require "./component/*"

require "big"

module Ven
  class Machine < Visitor
    private alias Num = MNumber
    private alias Str = MString
    private alias Vec = MVector

    # Maximum depth of calls (see 'call(MConcreteFunction, ...)')
    MAX_CALL_DEPTH = 500

    # Maximum amount of normalization passes (see 'normalize!')
    MAX_NORMALIZE_PASSES = 500

    # Maximum amount of compute cycles (see 'compute')
    MAX_COMPUTE_CYCLES = 1000

    def initialize(@context = Context.new)
      @computes = 0
    end

    ### Handling death

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
      die("'_' used outside of context: context stack is empty")
    end

    def visit!(q : QURef)
      @context.us.last
    rescue IndexError
      die("'&_' used outside of context: context stack is empty")
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
        die("could not spread over an empty vector")
      end

      result = [] of Model
      item = operand.value.first

      @context.local(nil, {q.tag, "<spread>"}) do
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

      Vec.new(result)
    end

    def visit!(q : QIf)
      if false?(visit(q.cond))
        return q.alt.nil? ? MHole.new : visit(q.alt.not_nil!)
      end

      visit(q.suc)
    end

    def visit!(q : QBlock)
      visit(q.body).last
    end

    def visit!(q : QAssign)
      @context.define(q.target, visit(q.value))
    end

    def visit!(q : QFun)
      # First, find out what the parameter types are. By
      # default, they're `any`
      rest = MType.new("any", Model)
      params = q.params.zip?(q.types).map do |param, type|
        type.nil? || (rest = visit(type)).is_a?(MType) \
          ? {param, rest.as(MType)}
          : die("this 'given' expression does not return a type: #{type}")
      end

      # Now we are able to create a concrete function:
      concrete = MConcreteFunction.new(q.tag, q.name, params, q.body)

      # Use the existing generic or create a new one
      unless (generic = @context.fetch(q.name)).is_a?(MGenericFunction)
        generic = @context.define(q.name, MGenericFunction.new(q.name))
      end

      unless generic.add(concrete)
        die("could not add #{concrete} to #{generic}: such implementation " \
            "already exists")
      end

      generic
    end

    def visit!(q : QCall)
      call(visit(q.callee), visit(q.args))
    end

    ### Helpers

    # Check if a thing is falsey, according to Ven. Note that
    # it returns Crystal's bool, not Ven's
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

    # `of?` checks if Model `left` is of the MType `right`
    def of?(left : Model, right : MType) : Bool
      right.type == Model ? true : left.class == right.type
    end

    # Yield an inverse of `false?`
    private macro true?(model)
      !false?({{model}})
    end

    # Call `true?` with `model` and make the result an MBool
    private macro to_bool(model)
      MBool.new(true?({{model}}))
    end

    ### Calls

    private def typecheck(params : Array(Ven::TypedParam), args : Array(Model))
      params.zip?(args).each do |param, arg|
        unless !arg.nil? && of?(arg, param[1])
          return false
        end
      end

      true
    end

    def call(callee : MConcreteFunction, args : Array(Model), typecheck = true)
      if typecheck && !typecheck(callee.params, args)
        # TODO: better error
        die("typecheck failed")
      end

      @context.local({callee.params.map(&.first), args}, {callee.tag, callee.name}) do
        @context.with_u(args.reverse) do
          if @context.trace.amount > MAX_CALL_DEPTH
            die("too many calls: very deep or infinite recursion")
          elsif (result = visit(callee.body).last).is_a?(MHole)
            die("illegal operation: #{callee} returned a hole")
          else
            result
          end
        end
      end
    end

    def call(callee : MGenericFunction, args)
      callee.concretes.each do |concrete|
        if concrete.params.size == args.size && typecheck(concrete.params, args)
          return call(concrete, args, typecheck: false)
        end
      end

      die("no concrete of #{callee} could receive these arguments: #{args.join(", ")}")
    end

    def call(callee : MVector, args)
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

      items.size > 1 ? MVector.new(items) : items.first
    end

    def call(callee : Model, args)
      die("could not call this callee: #{callee}")
    end

    ### Unary (prefix) operations

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
    rescue e : ModelCastError
      die("'#{operator}': cannot cast (to normalize) #{operand}: #{e.message}")
    end

    ### Binary operations

    # True if `left` and `right` need normalization to be
    # used with `operator`
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

    # Return a tuple {left, right} where left, right are
    # normalized `left`, `right` (i.e., converted according
    # to the specification, which can be found in `normalize?`)
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

    # Interpret the binary operations
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
        left = MBool.new(left.value == right.value)
      when {"is", Str, Str}
        left = MBool.new(left.value == right.value)
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

    # Top-level entry to the interpretation of binary operations
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
    rescue e : ModelCastError
      die("'#{operator}': cannot cast (to normalize): #{left}, #{right}: #{e.message}")
    end

    ### Interaction with the outside world

    def self.from(tree : Quotes, scope : Context)
      new(scope.clear).visit(tree)
    end
  end
end
