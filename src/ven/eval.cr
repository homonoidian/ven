require "./component/*"

require "big"

module Ven
  class Machine < Visitor
    private alias Num = MNumber
    private alias Str = MString
    private alias Vec = MVector

    # Maximum amount of traces (die of recursion if more)
    MAX_TRACE = 500

    # Maximum amount of normalization passes
    MAX_NORMALIZE_PASSES = 500

    def initialize(@context = Context.new)
      @computes = 0
    end

    ### Handling death (what a soothing name this is!)

    def die(message : String)
      # This method is required to be implemented. It is
      # actively used in Visitor, though, and has no uses
      # in this class. Macro `die` is used instead

      raise InternalError.new("no last node") if @last.nil?

      # Construct the stack trace in a clever (?) way
      # Note that traceback is in the Scope, which is (?) bad
      # since the scope is copied every function call.
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
      Num.new(str2num(q.value))
    end

    def visit!(q : QString)
      Str.new(q.value)
    end

    def visit!(q : QVector)
      Vec.new(visit(q.items))
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

      # Apply the operation on two first items to deduce
      # the type of the accumulator
      memo = binary(q.operator, body.value.first, body.value[1])

      body.value[2...].reduce(memo) do |acc, item|
        binary(q.operator, acc, item)
      end
    end

    def visit!(q : QLambdaSpread)
      operand = visit(q.operand)

      unless operand.is_a?(Vec)
        die("could not spread over this value: #{operand}")
      end

      result = [] of Model

      @context.local(nil, {q.tag, "<spread>"}) do
        operand.value.each_with_index do |item, index|
          @context.define("_", item)
          factor = visit(q.lambda)
          unless factor.is_a?(MBool) && !factor.value
            result << (factor.is_a?(MHole) ? item : factor)
          end
        end
      end

      Vec.new(result)
    end

    def visit!(q : QIf)
      if false? visit(q.cond)
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

    def visit!(q : QBasicFun)
      @context.define(q.name, MFunction.new(q.tag, q.name, q.params, q.body))
    end

    def visit!(q : QCall)
      callee, args = visit(q.callee), visit(q.args)

      if !callee.is_a?(MFunction)
        die("callee is not a function: #{callee}")
      elsif (exp = callee.params.size) != (fnd = q.args.size)
        die("#{callee} expected #{exp} argument(s), but found #{fnd}")
      end

      @context.local({callee.params, args}, trace: {callee.tag, callee.name}) do
        if @context.trace.amount > MAX_TRACE
          die("too many calls: very deep or infinite recursion")
        elsif (result = visit(callee.body).last).is_a?(MHole)
          die("illegal operation: #{callee} returned a hole")
        else
          result
        end
      end
    end

    ### Helpers

    # `false?` is the helper identity contexts and statements
    # use to check if a thing is falsey. Note that it returns
    # Crystal's bool, not Ven's
    def false?(model : Model) : Bool
      case model
      when Vec
        model.value.all? { |item| false?(item) }
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

    # Yield an inverse of `true?`
    private macro true?(model)
      !false?({{model}})
    end

    # Construct an MBool based on `true?`
    private macro to_bool(model)
      MBool.new(true?({{model}}))
    end

    # A method to convert String to BigFloat and have the
    # same death rescuing ArgumentError
    def str2num(str : String)
      str.to_big_f
    rescue ArgumentError
      die("'#{str}': not a base-10 number")
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
    end

    ### Binary operations

    # True if `left` and `right` need normalization to be
    # used with `operator`
    def normalize?(operator, left : Model, right : Model)
      case {operator, left, right}
      # when {"is", MBool, MBool}
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
        # so there is no need nor support for normalization
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
        # -> Balance both sides: {Vec, Vec} | {Str, Str} ...
        # 'is' is one of the few operators that have no fallback,
        # meaning it can sometimes fail (e.g., fun is fun)
        when {Vec, _}, {_, Vec}
          {left.to_vec, right.to_vec}
        when {Str, _}, {_, Str}
          {left.to_str, right.to_str}
        when {Num, _}, {_, Num}
          {left.to_num, right.to_num}
        when {MBool, _}
          {left, to_bool(right)}
        when {_, MBool}
          {to_bool(left), right}
        end
      when "<", ">", "<=", ">="
        # -> {Num, Num}
        {left.to_num, right.to_num}
      when "+", "-", "*", "/" then case {left, right}
        # -> {Vec, Vec} | {Num, Num}
        when {Vec, _}, {_, Vec}
          # -> [] <> _, _ <> [] -> [] <> [] -> {Vec, Vec}
          {left.to_vec, right.to_vec}
        else
          {left.to_num, right.to_num}
        end
      when "~" then case {left, right}
        # -> {Vec, Vec} | {Str, Str}
        when {Vec, _}, {_, Vec}
          # -> [] ~ _, _ ~ [] -> [] ~ [] -> {Vec, Vec}
          {left.to_vec, right.to_vec}
        when {Str, _}, {_, Str}
          # _ ~ "", "" ~ _ -> "_" ~ "", "" ~ "_" -> {Str, Str}
          {left.to_str, right.to_str}
        else
          # _ ~ _ -> [_] ~ [_] -> {Vec, Vec}
          {left.to_vec, right.to_vec}
        end
      when "x" then case {left, right}
        # -> {Vec, Num} | {Str, Num}
        when {_, Vec}, {_, Str}
          # _ x [...] -> {Num, Vec} -> (commutative) -> {Vec, Num}
          {right, left.to_num}
        when {Vec, _}, {Str, _}
          # [...] x _, "" x _ -> {Vec, Num}, {Str, Num}
          {left, right.to_num}
        else
          # _ x _ -> {Vec, Num}
          {left.to_vec, right.to_num}
        end
      end || die("'#{operator}': could not normalize these operands: #{left}, #{right}")
    end

    # Interpret the binary operations
    def compute(operator, left : Model, right : Model)
      if (@computes += 1) > 1000
        die("too many compute cycles; you've probably found " \
            "an implementation bug: normalizing this operator " \
            "('#{operator}') causes an infinite loop")
      end

      # `left` is going to be changed throughout `compute`
      # Shallowly (XXX right?) un-link it from the original Model
      left = left.dup

      case {operator, left, right}
      when {"is", Num, Num}
        left = MBool.new(left.value == right.value)
      when {"is", Str, Str}
        left = MBool.new(left.value == right.value)
      when {"is", MBool, MBool}
        left.value = left.value == right.value
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
        left.value /= right.value.to_big_f
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
    end

    # The gateway to binary operations machinery.
    def binary(operator, left : Model, right : Model)
      passes = 0

      # Normalize until satisfied
      while normalize?(operator, left, right)
        if (passes += 1) > MAX_NORMALIZE_PASSES
          die("too many normalization passes; you've probably " \
              "found an implementation bug, as '#{operator}' " \
              "requested normalization (thus was not normalized " \
              "into one of the computable forms) more than " \
              "#{MAX_NORMALIZE_PASSES} passes")
        end
        left, right = normalize!(operator, left, right)
      end

      compute(operator, left, right)
    rescue e : ModelCastError
      die("'#{operator}': cast error for #{left}, #{right}: #{e.message}")
    end

    ### Interaction with the outside world

    def self.from(tree : Quotes, scope : Context)
      new(scope.clear).visit(tree)
    end
  end
end
