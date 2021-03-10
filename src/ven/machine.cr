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

    # Returns the instruction at the IP. If there are no
    # instructions left, returns nil.
    private macro fetch
      if @ip < @chunk.size
        @chunk[@ip]
      end
    end

    # Returns the instruction at the IP.
    private macro fetch!
      @chunk[@ip]
    end

    # Resolves the argument of the current instruction. *cast*
    # is what type the resolved value is ought to be.
    private macro argument(cast = String)
      @chunk.resolve(@chunk[@ip]).as({{cast}})
    end

    # Pushes *models* onto the stack if *condition* is true.
    # Bool false is pushed otherwise. *condition* may be omitted;
    # in that case, *models* will all just be pushed.
    private macro put(*models, if condition = nil)
      {% if condition %}
        if {{condition}}
          {% for model in models %}
            @stack << ({{model}})
          {% end %}
        else
          @stack << bool false
        end
      {% else %}
        {% for model in models %}
          @stack << ({{model}})
        {% end %}
      {% end %}
    end

    # Pops a model from the stack.
    private macro pop
      @stack.pop
    end

    # Pops *amount* models and returns a **reversed** array
    # of them. If a block is given, deconstructs this array
    # and passes it to the block. The items of the array are
    # **all** assumed to be of the type *type*. Alternatively,
    # types for each item individually may be provided by
    # giving *type* a tuple literal.
    private macro pop(amount, are type = Model, &block)
      %models = Models.new

      {{amount}}.times do
        %models << pop
      end

      %models.reverse!

      {% if block %}
        {% for argument, index in block.args %}
          {{argument}} = %models[{{index}}]
            .as({{type.is_a?(TupleLiteral) ? type[index] : type}})
        {% end %}

        {{yield}}
      {% end %}
    end

    # A shorthand for `Num.new`.
    private macro num(value)
      Num.new({{value}})
    end

    # A shorthand for `Str.new`.
    private macro str(value)
      Str.new({{value}})
    end

    # A shorthand for `Vec.new`.
    private macro vec(value)
      Vec.new({{value}})
    end

    # A shorthand for `MBool.new`.
    private macro bool(value)
      MBool.new({{value}})
    end

    # A shorthand for `MRegex.new`.
    private macro regex(value)
      MRegex.new({{value}})
    end

    # A short way of writing simple binary operations (those
    # that map directly to Crystal's). Takes two operands from
    # the stack, of types *input*, and applies a binary *operator*
    # to their `.value`s. It then converts the result of the
    # application into the desired type with *output*, and
    # puts this result back onto the stack.
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
        # -- false
        when :SYM then put bool false
        # -- (a : num)
        when :NUM then put num argument
        # -- (a : str)
        when :STR then put str argument
        # -- (a : regex)
        when :PCRE then put regex argument
        # -- (a : vec)
        when :VEC then put vec (pop argument Int32)
        # -- true
        when :TRUE then put bool true
        # -- false
        when :FALSE then put bool false
        # [NEGATE] (a : num) -- (a' : num)
        when :NEG then put pop.to_num.neg!
        # [TO NUM] (a : any) -- (a : num)
        when :TON then put pop.to_num
        # [TO STR] (a : any) -- (a : str)
        when :TOS then put pop.to_str
        # [TO BOOL] (a : any) -- (a : bool)
        when :TOB then put pop.to_bool
        # [TO INVERSE BOOL] (a : any) -- ('a : bool)
        when :TOIB then put pop.to_bool(inverse: true)
        # [LENGTH] (a : any) -- ('a : num)
        when :LEN
          this = pop

          this.is_a?(Str | Vec) \
            ? put num this.value.size
            : put num this.to_s.size
        # [NORMALIZE] (a : any) (b : any) -- 'a 'b
        when :NOM
          pop 2 do |left, right|
            begin
              case operator = argument
              when "in" then case {left, right}
                when {_, Str}
                  put left.to_str, right
                when {_, Vec}
                  put left, right
                end
              when "is" then case {left, right}
                when {Vec, _}, {_, Vec}
                  put left.to_vec, right.to_vec
                when {_, MRegex}
                  put left.to_str, right
                when {Str, _}
                  put left, right.to_str
                when {Num, _}
                  put left, right.to_num
                when {MBool, _}, {_, MBool}
                  put left.to_bool, right.to_bool
                end
              when "<", ">", "<=", ">="
                put left.to_num, right.to_num
              when "+", "-", "*", "/"
                put left.to_num, right.to_num
              when "~"
                put left.to_str, right.to_str
              when "&"
                put left.to_vec, right.to_vec
              when "x" then case {left, right}
                when {_, Vec}, {_, Str}
                  put right, left.to_num
                when {Vec, _}, {Str, _}
                  put left, right.to_num
                else
                  put left.to_vec, right.to_num
                end
              end ||
                die("'#{operator}': cannot normalize #{left}, #{right}" \
                    "(try changing the order)")
            rescue e : ModelCastException
              die("'#{operator}': cannot normalize #{left}, #{right}" \
                  "(#{e.message})")
            end
          end
        # [in CONTAINER EQUAL by VALUE] a (b : vec | str) -- a?
        when :CEQV
          pop 2 do |left, right|
            case right
            when Vec
              put left, if: right.value.any? &.eqv?(left)
            when Str
              put left, if: right.value.includes?(left.as(Str).value)
            end
          end
        # [EQUAL] a b -- a?
        when :EQU
          pop 2 do |left, right|
            case {left, right}
            when {_, MType}
              put bool left.of?(right)
            when {Str, MRegex}
              put str($0), if: left.value =~ right.value
            when {MBool | Num | Str | Vec, _}
              put left, if: left.eqv?(right)
            end
          end
        # [LESS THAN] (a : num) (b : num) -- (a' : bool)
        when :LT then binary(:<, output: bool)
        # [GREATER THAN] (a : num) (b : num) -- (a' : bool)
        when :GT then binary(:>, output: bool)
        # [LESS THAN EQUAL to] (a : num) (b : num) -- (a' : bool)
        when :LTE then binary(:<=, output: bool)
        # [GREATER THAN EQUAL to] (a : num) (b : num) -- (a' : bool)
        when :GTE then binary(:>=, output: bool)
        # (a : num) (b : num) -- (a' : num)
        when :ADD then binary(:+)
        # (a : num) (b : num) -- (a' : num)
        when :SUB then binary(:-)
        # (a : num) (b : num) -- (a' : num)
        when :MUL then binary(:*)
        # (a : num) (b : num) -- (a' : num)
        when :DIV then binary(:/)
        # (a : vec) (b : vec) -- (a' : vec)
        when :PEND then binary(:+, input: Vec, output: vec)
        # (a : str) (b : str) -- (a' : str)
        when :CONCAT then binary(:+, input: Str, output: str)
        # (a : any) (b : num) -- (a' : str | vec)
        when :TIMES
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
        # [ENSURE] a --
        when :ENS then die("ensure: got a falsey value") if pop.false?
        # [JUMP OVER IF TRUE] a -- a?
        when :JOIT
          unless (value = pop).false?
            put value

            next @ip += argument(Int32)
          end
        # [JUMP OVER IF FALSE] a -- a?
        when :JOIF
          if (value = pop).false?
            put value

            next @ip += argument(Int32)
          end
        when :INK
          args, name = pop(argument Int32), pop

          if name.is_a?(Num) && name.value == 1
            puts args.join("\n")
          elsif !name.callable?
            die("this callee is not callable: #{name}")
          elsif name.is_a?(Vec | Str)
            found =
              args.map do |index|
                if !index.is_a?(Num)
                  die("improper index value: #{index}")
                elsif index.value >= name.size
                  die("index out of bounds: #{index}")
                end

                name[index.value.to_i]
              end

            put (found.size == 1 ? found.first : vec found)
          end
        else
          raise InternalError.new("unknown opcode: #{this.opcode}")
        end

        @ip += 1
      end
    end
  end
end
