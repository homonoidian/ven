require "./suite/*"

module Ven
  class Machine
    include Suite

    # The instruction pointers. There are many, because every
    # function et al. requires its own instruction pointer.
    @ips = [0]

    def initialize(@chunks : Chunks, @context : Context)
      @stacks = [Models.new]
    end

    # Returns the current chunk. The first chunk of `@chunks`
    # is thought of as the current.
    private macro chunk
      @chunks.first
    end

    # Returns the current stack. The last stack of `@stacks`
    # is thought of as the current.
    private macro stack
      @stacks.last
    end

    # Dies of runtime error with *message*, which should explain
    # why the error happened.
    def die(message : String)
      raise RuntimeError.new(chunk.file, fetch!.line, message)
    end

    # Returns the instruction at the current instruction pointer,
    # or nil if there are no instructions left to fetch.
    private macro fetch?
      if (%ip = @ips.last) < chunk.size
        chunk[%ip]
      end
    end

    # Returns the instruction at the current instruction pointer.
    # Raises if there is no instructions left to fetch.
    private macro fetch!
      chunk[@ips.last]
    end

    # Increments the current instruction pointer.
    private macro goto
      @ips[-1] += 1
    end

    # Sets the current instruction pointer to *ip*.
    private macro goto(ip)
      @ips[-1] = {{ip}}
    end

    # Sets the instruction pointer to *ip* and `next`s. Must
    # be called only inside a loop.
    private macro goto!(ip)
      next goto({{ip}})
    end

    # A `next` that can be safely used in the Machine's
    # evaluation loop.
    private macro next!(value)
      {{value}}

      next goto
    end

    # Resolves the argument of the current instruction. *cast*
    # is what type the resolved value should be cast into.
    private macro argument(cast = String)
      chunk.resolve(fetch!).as({{cast}})
    end

    # Pushes *models* onto the stack if *condition* is true.
    # Pushes `bool` false if it isn't. *condition* may be
    # omitted.
    private macro put(*models, if condition = nil)
      {% if condition %}
        if {{condition}}
          {% for model in models %}
            stack << ({{model}})
          {% end %}
        else
          stack << bool false
        end
      {% else %}
        {% for model in models %}
          stack << ({{model}})
        {% end %}
      {% end %}
    end

    # Pops a model from the stack.
    private macro pop
      stack.pop
    end

    # Pops *amount* models from the stack and returns a reversed
    # (if *reverse* is true) array of them. If a block is given,
    # deconstructs this array and passes it to the block. The
    # items of the array are **all** assumed to be of the type
    # *type*. Alternatively, types for each item individually
    # may be provided by giving *type* a tuple literal.
    private macro pop(amount, are type = Model, reverse = true, &block)
      %models = Models.new

      {{amount}}.times do
        %models << pop
      end

        %models
        {% if reverse %}
          .reverse!
        {% end %}

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

    # Does a `Context.fetch` call and dies if got nil.
    private macro var(name)
      @context.fetch(%symbol = {{name}}) || die("symbol not found: #{%symbol}")
    end

    # A shorthand for simple binary operations (those that map
    # directly to Crystal's). Takes two operands from the stack,
    # of types *input*, and applies the *operator* to their
    # `.value`s. It then passes the result to *output*, and
    # places the result of that onto the stack.
    private macro binary(operator, input = Num, output = num)
      pop(2, {{input}}) do |left, right|
        put {{output}}(left.value {{operator.id}} right.value)
      end
    end

    # Performs a concrete (or concrete-like) invokation. Uses
    # `next`, so requires a loop around itself. *args* is the
    # arguments to the concrete, and *chunk* is the chunk that
    # will be evaluated.
    private macro invoke!(chunk, args = Models.new)
      @stacks << {{args}}
      @chunks.unshift({{chunk}})
      @context.push

      next @ips << 0
    end

    # Reverts the result of an invokation. Essentialy, an
    # antagonist of `invoke!`. Bool *transfer* determines
    # whether to transfer the child stack's last stackee
    # to the parent stack (e.g. return)
    private macro uninvoke(transfer = false)
      @ips.pop
      %child = @stacks.pop
      @chunks.shift
      @context.pop

      {% if transfer %}
        if %stackee = %child.last?
          put %stackee
        end
      {% else %}
        true
      {% end %}
    end

    # Typechecks *args* against *types*. Uses both `of?` and
    # `eqv?` to do this.
    def typecheck(types : Models, args : Models) : Bool
      types.zip(args).each do |type, arg|
        unless arg.of?(type) || type.eqv?(arg)
          return false
        end
      end

      true
    end

    # Starts the evaluation loop, which begins to fetch the
    # instructions from the current chunk and execute them,
    # until there aren't any left.
    def start
      while this = fetch?
        case this.opcode
        # -- a
        when :SYM
          put var argument
        # -- (a : num)
        when :NUM
          put num argument
        # -- (a : str)
        when :STR
          put str argument
        # -- (a : regex)
        when :PCRE
          put regex argument
        # -- (a : vec)
        when :VEC
          put vec (pop argument Int32)
        # -- true
        when :TRUE
          put bool true
        # -- false
        when :FALSE
          put bool false
        # [NEGATE] (a : num) -- (a' : num)
        when :NEG
          put pop.to_num.neg!
        # [TO NUM] (a : any) -- (a : num)
        when :TON
          put pop.to_num
        # [TO STR] (a : any) -- (a : str)
        when :TOS
          put pop.to_str
        # [TO BOOL] (a : any) -- (a : bool)
        when :TOB
          put pop.to_bool
        # [TO INVERSE BOOL] (a : any) -- ('a : bool)
        when :TOIB
          put pop.to_bool(inverse: true)
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
                  next! put left.to_str, right
                when {_, Vec}
                  next! put left, right
                end
              when "is" then case {left, right}
                when {_, MType}, {_, MAny}
                  next! put left, right
                when {Vec, _}, {_, Vec}
                  next! put left.to_vec, right.to_vec
                when {_, MRegex}
                  next! put left.to_str, right
                when {Str, _}
                  next! put left, right.to_str
                when {Num, _}
                  next! put left, right.to_num
                when {MBool, _}, {_, MBool}
                  next! put left.to_bool, right.to_bool
                end
              when "<", ">", "<=", ">="
                next! put left.to_num, right.to_num
              when "+", "-", "*", "/"
                next! put left.to_num, right.to_num
              when "~"
                next! put left.to_str, right.to_str
              when "&"
                next! put left.to_vec, right.to_vec
              when "x" then case {left, right}
                when {_, Vec}, {_, Str}
                  next! put right, left.to_num
                when {Vec, _}, {Str, _}
                  next! put left, right.to_num
                else
                  next! put left.to_vec, right.to_num
                end
              end
            rescue e : ModelCastException
              # fallthrough
            end

            die("'#{operator}': cannot normalize #{left}, #{right} " \
                 "(#{e.try(&.message) || "try changing the order"})")
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
            when {_, MType}, {_, MAny}
              put bool left.of?(right)
            when {Str, MRegex}
              put str($0), if: left.value =~ right.value
            when {MBool, MBool}
              # A fallback for scenarios like this: false is false.
              put bool left.eqv?(right)
            else
              put left, if: left.eqv?(right)
            end
          end
        # [LESS THAN] (a : num) (b : num) -- (a' : bool)
        when :LT
          binary(:<, output: bool)
        # [GREATER THAN] (a : num) (b : num) -- (a' : bool)
        when :GT
          binary(:>, output: bool)
        # [LESS THAN EQUAL to] (a : num) (b : num) -- (a' : bool)
        when :LTE
          binary(:<=, output: bool)
        # [GREATER THAN EQUAL to] (a : num) (b : num) -- (a' : bool)
        when :GTE
          binary(:>=, output: bool)
        # (a : num) (b : num) -- (a' : num)
        when :ADD
          binary(:+)
        # (a : num) (b : num) -- (a' : num)
        when :SUB
          binary(:-)
        # (a : num) (b : num) -- (a' : num)
        when :MUL
          binary(:*)
        # (a : num) (b : num) -- (a' : num)
        when :DIV
          binary(:/)
        # (a : vec) (b : vec) -- (a' : vec)
        when :PEND
          binary(:+, input: Vec, output: vec)
        # (a : str) (b : str) -- (a' : str)
        when :CONCAT
          binary(:+, input: Str, output: str)
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
        when :ENS
          die("ensure: got a falsey value") if pop.false?
        # [GOTO] --
        when :G
          goto! (argument Int32)
        # [GOTO IF TRUE] a -- a?
        when :GIT
          unless (value = pop).false?
            put value; goto! argument Int32
          end
        # [GOTO IF FALSE] a -- a?
        when :GIF
          if (value = pop).false?
            put value; goto! argument Int32
          end
        # a --
        when :LOCAL
          @context.define(argument, pop)
        # a --
        when :GLOBAL
          @context.define(argument, pop, global: true)
        # a -- a
        when :LOCAL_PUT
          put @context.define(argument, pop)
        # a -- a
        when :GLOBAL_PUT
          put @context.define(argument, pop, global: true)
        # [REMAINING TO VEC] * -- (a : vec)
        when :REM_TO_VEC
          put vec (pop stack.size, reverse: false)
        # ...types --
        when :FUN
          code = @chunks[argument Int32]
          name = code.name
          given = code.meta[:given].as(Int32)
          types = pop given
          defee = MConcreteFunction.new(types, code)

          case existing = @context.fetch(name)
          when MGenericFunction
            next! existing.add(defee)
          when MConcreteFunction
            if existing != defee
              defee = MGenericFunction
                .new(name)
                .add!(existing)
                .add!(defee)
            end
          end

          @context.define(name, defee)
        # a ...b -- a
        when :CALL
          args, callee = pop(argument Int32), pop

          case callee
          when Vec, Str
            items = args.map do |index|
              if !index.is_a?(Num)
                die("improper item index value: #{index}")
              elsif index.value >= callee.size
                die("item index out of bounds: #{index}")
              end

              callee[index.value.to_i]
            end

            put (items.size == 1 ? items.first : vec items)
          when MFunction
            index, found, current = -1, false, callee

            until found
              if callee.is_a?(MGenericFunction)
                break if index >= callee.size

                # Go to the next variant right away:
                current = callee[index += 1]
              end

              if current.is_a?(MConcreteFunction)
                count = args.size
                arity = current.arity
                slurpy = current.slurpy
                found =
                  ((slurpy && count >= arity) ||
                   (!slurpy && count == arity)) &&
                  typecheck(current.types, args)

                break if !found && index == -1
              end
            end

            unless found
              die("improper arguments for #{callee}: #{args.join(", ")}")
            end

            invoke!(current.as(MConcreteFunction).code, args.reverse!)
          else
            die("illegal callee: #{callee}")
          end
        # a --> a
        when :RET
          unless uninvoke(transfer: true)
            die("void functions illegal")
          end
        else
          raise InternalError.new("unknown opcode: #{this.opcode}")
        end

        goto
      end
    end

    # Returns the result of this Machine's work.
    def result?
      stack.last?
    end
  end
end