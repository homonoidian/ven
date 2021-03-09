require "./suite/*"

module Ven
  class Machine
    include Suite

    # Instruction pointer (index of the current instruction
    # in `@chunk`).
    @ip : Int32 = 0

    # The chunk in execution.
    @chunk : Chunk

    def initialize(@chunks : Chunks)
      @stack = Models.new
      @chunk = @chunks.last
    end

    def die(message : String)
      raise RuntimeError.new(@chunk.file, fetch!.line, message)
    end

    # Returns the instruction at IP. If there is no instruction
    # left, returns nil.
    private macro fetch
      if @ip < @chunk.size
        @chunk[@ip]
      end
    end

    # Returns the instruction at IP.
    private macro fetch!
      @chunk[@ip]
    end

    # Resolves the argument of the current instruction. *cast*
    # is what type the resolved value should be.
    private macro argument(cast = String)
      @chunk.resolve(@chunk[@ip]).as({{cast}})
    end

    # Pushes *models* onto the stack.
    private macro put(*models)
      {% for model in models %}
        @stack << ({{model}})
      {% end %}
    end

    # Pops a model from the stack.
    private macro pop
      @stack.pop
    end

    # Pops *amount* models and returns an array of them,
    # reversing this array. If a block is given, deconstructs
    # this array and passes it to the block. The items of the
    # array are **all** assumed to be of the type *type*.
    # Alternatively, types for each item individually may be
    # provided by giving *type* a tuple literal.
    private macro pop(amount, are type = Model, &block)
      %models = Models.new

      {{amount}}.times do
        %models << pop
      end

      %models.reverse!

      {% if block %}
        {% for argument, index in block.args %}
          {% if type.is_a?(TupleLiteral) %}
            {{argument}} = %models[{{index}}].as({{type[index]}})
          {% else %}
            {{argument}} = %models[{{index}}].as({{type}})
          {% end %}
        {% end %}

        {{yield}}
      {% end %}
    end

    # A shorthand for `Num.new(value)`.
    private macro num(value)
      Num.new({{value}})
    end

    # A shorthand for `Str.new(value)`.
    private macro str(value)
      Str.new({{value}})
    end

    # A shorthand for `Vec.new(value)`.
    private macro vec(value)
      Vec.new({{value}})
    end

    # A shorthand for `MBool.new(value)`.
    private macro bool(value)
      MBool.new({{value}})
    end

    # `may_be` is a `put` that pushes `bool` false if the *value*
    # is Crystal falsey.
    private macro may_be(value)
      (%value = {{value}}) ? put %value : put bool false
    end

    # Sets *value*'s `truth` to true and returns the value
    # back, but only if *condition* is true. If it is not,
    # returns `bool` false. See `Model.truth?`.
    private macro truthy(value, if condition)
      {{condition}} ? truthy {{value}} : bool false
    end

    # Sets *value*'s `truth` to true and returns the value
    # back. See `Model.truth?`.
    private macro truthy(value)
      %value = {{value}}
      %value.truth = true
      %value
    end

    # A short way of writing simple binary operations (those
    # that map directly to Crystal's). Takes two operands from
    # the stack, of types *input*, and applies a binary *operator*
    # to their `.value`s. It then converts the result of the
    # application into a desired type with *output*, and puts
    # this result back onto the stack.
    private macro binary(operator, input = Num, output = num)
      pop(2, {{input}}) do |left, right|
        put {{output}}(left.value {{operator.id}} right.value)
      end
    end

    # Starts the evaluation loop, which begins to fetch the
    # instructions from the current chunk and execute them,
    # until there aren't left any.
    def start
      while this = fetch
        case this.opcode
        when :SYM
          put bool false
        when :NUM # -- a
          put Num.new(argument)
        when :STR # -- a
          put Str.new(argument)
        when :PCRE # -- a
          put MRegex.new(argument)
        when :VEC # -- a
          put Vec.new(pop argument Int32)
        when :TRUE # -- a
          put bool true
        when :FALSE # -- a
          put bool false
        when :NEG # a -- a'
          put -pop.to_num
        when :TON # a -- a'
          put pop.to_num
        when :TOS # a -- a'
          put pop.to_str
        when :TOB # a -- a'
          put pop.to_bool
        when :TOIB # a -- a'
          put pop.to_bool(inverse: true)
        when :LEN # a -- a'
          this = pop

          this.is_a?(Str | Vec) \
            ? put Num.new(this.value.size)
            : put Num.new(this.to_s.size)
        when :NOM # a b -- a' b'
          left, right = pop 2

          begin
            normalized =
              case operator = argument
              when "in" then case {left, right}
                when {_, Str}
                  {left.to_str, right}
                when {_, Vec}
                  {left, right}
                end
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
                  {left.to_bool, right.to_bool}
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
              end
          rescue e : ModelCastException
            die("'#{operator}': cannot normalize #{left}, #{right}: #{e.message}")
          end

          # `normalized` is false or nil if normalization failed.
          unless normalized
            die("'#{operator}': could not normalize these operands: " \
                "#{left}, #{right} (try changing the order)")
          end

          # Put them back on the stack.
          put normalized[0], normalized[1]
        when :CEQV # a b -- a'
          found =
            pop 2 do |left, right|
              case right
              when Vec
                right.value.each do |item|
                  break item if left.eqv?(item)
                end
              when Str
                # If `right` is a Str, `left` is a Str too
                # (see NOM).
                left = left.as(Str)

                right.value.chars.each do |char|
                  break str(char.to_s) if left.value == char
                end
              end
            end

          may_be found
        when :EQU # a b -- a'
          pop 2 do |left, right|
            case {left, right}
            when {_, MType}
              put bool left.of?(right)
            when {Str, MRegex}
              put truthy Str.new($0), if: left.value =~ right.value
            when {MBool | Num | Str | Vec, _}
              put truthy left, if: left.eqv?(right)
            end
          end
        when :LTE # a b -- a'
          binary(:<=, output: bool)
        when :GTE # a b -- a'
          binary(:>=, output: bool)
        when :LT # a b -- a'
          binary(:<, output: bool)
        when :GT # a b -- a'
          binary(:>, output: bool)
        when :ADD # a b -- a'
          binary(:+)
        when :SUB # a b -- a'
          binary(:-)
        when :MUL # a b -- a'
          binary(:*)
        when :DIV # a b -- a'
          binary(:/)
        when :PEND # a b -- a'
          binary(:+, input: Vec, output: vec)
        when :CONCAT # a b -- a'
          binary(:+, input: Str, output: str)
        when :TIMES # a b -- a'
          pop 2, {Model, Num} do |left, right|
            amount = right.value.to_big_i

            # There are two possibilities here (see NOM):
            # either `left` is a Vec, or a Str.
            case left
            when Vec
              put vec left.value * amount
            when Str
              put str left.value * amount
            end
          end
        when :ENS # a --
          if pop.is_bool_false?
            die("ensure: got a falsey value")
          end
        when :JOIT # a -- [a if a is not false]
          unless (it = pop).is_bool_false?
            put it

            next @ip += argument(Int32)
          end
        when :JOIF # a -- [a if a is false]
          if (it = pop).is_bool_false?
            put it

            next @ip += argument(Int32)
          end
        when :IVK # a ... -- a'
          args, name = pop(argument Int32), pop

          if name.is_a?(Str) && name.value == "say"
            puts args.join("\n")

            # Put back on the stack as Vec: say returns
            # unchanged.
            put Vec.new(args)
          else
            die("this callee is not callable: #{name}")
          end
        else
          raise InternalError.new("unknown opcode: #{this.opcode}")
        end

        @ip += 1
      end
    end
  end
end
