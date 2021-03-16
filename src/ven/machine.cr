require "./suite/*"

module Ven
  # :nodoc:
  alias Timetable = Hash(Int32, Time::Span)

  # Frame represents the current state of the `Machine`.
  class Frame
    alias Models = Suite::Models

    # Instruction pointer of this frame.
    property ip : Int32 = 0

    # The operand stack.
    property stack : Models

    # The control stack.
    property control = Array(Int32).new

    # The underscores (context) stack.
    property underscores = Models.new

    def initialize(@stack = Models.new)
    end

    delegate :last, :last?, to: @stack

    def to_s(io)
      io << "stack: " << @stack.join(" ") << "\n"
      io << "control: " << @control.join(" ") << "\n"
      io << "underscores: " << @underscores.join(" ") << "\n"
    end
  end

  class Machine
    include Suite

    # Timetable contains individual execution times of the
    # instructions this machine evaluated. Execution times
    # for repeatedly executing instructions are summed (e.g.,
    # for an instruction in a loop).
    getter timetable : Timetable

    # Fancyline used by the debugger.
    @@fancy = Fancyline.new

    @frames = [Ven::Frame.new]

    def initialize(@chunks : Chunks, @context : Context)
      @timetable = Timetable.new
    end

    # Returns the current frame. The last frame of `@frames`
    # is thought of as the current.
    private macro frame
      @frames.last
    end

    # Returns the current chunk. The first chunk of `@chunks`
    # is thought of as the current.
    private macro chunk
      @chunks.first
    end

    # Returns the current stack.
    private macro stack
      frame.stack
    end

    # Dies of runtime error with *message*, which should explain
    # why the error happened.
    def die(message : String)
      raise RuntimeError.new(chunk.file, fetch!.line, message)
    end

    # Returns the instruction at the current instruction pointer,
    # or nil if there are no instructions left to fetch.
    private macro fetch?
      if (%ip = frame.ip) < chunk.size
        chunk[%ip]
      end
    end

    # Returns the instruction at the current instruction pointer.
    # Raises if there is no instructions left to fetch.
    private macro fetch!
      chunk[frame.ip]
    end

    # Increments the current instruction pointer.
    private macro goto
      frame.ip += 1
    end

    # Sets the current instruction pointer to *ip*.
    private macro goto(ip)
      frame.ip = {{ip}}
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
            frame.stack << ({{model}})
          {% end %}
        else
          frame.stack << bool false
        end
      {% else %}
        {% for model in models %}
          frame.stack << ({{model}})
        {% end %}
      {% end %}
    end

    # Returns the last value on the stack. Can be seen (but
    # is not implemented as) as `put pop`.
    private macro tap
      frame.stack[-1]
    end

    # Pops a model from the stack.
    private macro pop
      frame.stack.pop
    end

    # Pops *amount* models from the stack and returns a reversed
    # (if *reverse* is true) array of them. If a block is given,
    # deconstructs this array and passes it to the block. The
    # items of the array are *all* assumed to be of the type
    # *cast*. It is possible, though, to specify the type of
    # each item individually, by passing *cast* a tuple literal.
    private macro pop(amount, are cast = Model, reverse = true, &block)
      %made = Models.new(%amount = {{amount}})

      %amount.times do
        %made
          {% if reverse %}
            .unshift(pop)
          {% else %}
            .<<(pop)
          {% end %}
      end

      {% if block %}
        {% for argument, index in block.args %}
          {% type = cast.is_a?(TupleLiteral) ? cast[index] : cast %}

          {{argument}} = %made[{{index}}].as({{type}})
        {% end %}

        {{yield}}
      {% else %}
        %made
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

    # Tries to retrieve a variable, *name*, and dies if failed to.
    private macro var(name)
      @context.fetch(%symbol = {{name}}) || die("symbol not found: #{%symbol}")
    end

    # A shorthand for simple binary operations (those that map
    # directly to Crystal's). Takes two operands from the stack,
    # of types *input*, and applies the *operator* to their
    # `.value`s. It then passes the result to *output*, and
    # places the result of that onto the stack. Properly dies
    # on division by zero.
    private macro binary(operator, input = Num, output = num)
      pop(2, {{input}}) do |left, right|
        begin
          put {{output}}(left.value {{operator.id}} right.value)
        rescue DivisionByZeroError
          die("'{{operator.id}}': division by zero given #{left}, #{right}")
        end
      end
    end

    # Performs a concrete (or concrete-like) invokation. Uses
    # `next`, and therefore has to be surrounded by a loop.
    # *args* are the arguments to the concrete, and *chunk*
    # is the chunk that will be evaluated.
    private macro invoke!(chunk, args = Models.new)
      @frames << Frame.new({{args}})
      @chunks.unshift({{chunk}})
      next @context.push
    end

    # An antagonist of `invoke!`. Bool *transfer* determines
    # whether to transfer the child's last stackee to the
    # parent stack (e.g. return)
    private macro uninvoke(transfer = false)
      @chunks.shift
      @context.pop

      {% if transfer %}
        if last = @frames.pop.last?
          put last
        end
      {% else %}
        @frames.pop

        true
      {% end %}
    end

    # Typechecks (orelse `eqv?`s) *args* against *types*. Makes
    # the lattermost type cover the excess arguments, if any.
    # **Will crash of memory error if *types* is empty.**
    def typecheck(types : Models, args : Models) : Bool
      last = uninitialized Model

      args.zip?(types) do |arg, type|
        type ? (last = type) : (type = last)

        unless arg.of?(type) || type.eqv?(arg)
          return false
        end
      end

      true
    end

    # A tiny, debugger-like state inspector.
    def debug(command : String, instruction : Instruction) : Bool
      if command.in?(".", ".i", ".instruction")
        puts instruction
      elsif command.in?(".s", ".stack")
        puts stack.join(" ")
      elsif command.in?(".u", ".underscores")
        puts frame.underscores.join(" ")
      elsif command.in?(".c", ".control")
        puts frame.control.join(" ")
      elsif command.in?(".h", ".help")
        puts "Available commands: . (.i, .instruction) .s (.stack) " \
             ".u (.underscores) .c (.control) .h (.help)"
      else
        puts @context.fetch(command) || "no such variable: #{command}"
      end

      true
    end

    # Starts the evaluation loop, which begins to fetch the
    # instructions from the current chunk and execute them,
    # until there aren't any left.
    def start(debug = false)
      remnants = false

      while this = fetch?
        if debug
          # Launches a tiny, crapcoded debugger. Not very
          # useful right now, but might very well be later.

          begin
            puts "Hit CTRL+C to step, or CTRL+D to skip all"

            loop do
              unless command = @@fancy.readline("#{frame.ip}, in #{chunk.name} >>> ")
                remnants = @@fancy.readline("Print remnant frames? (y/n) ") == "y"

                # EOF goes out of debug for the rest of this
                # `start`.
                break debug = false
              end

              debug(command, this.as Instruction)
            end
          rescue Fancyline::Interrupt
            puts
          end
        end

        took = Time.measure do
          case this.opcode
          # [DUPLICATE] a -- a a
          when :DUP
            put stack.last
          # [MOVE LAST (ONE) UP] a1 a2 -- a2 a1
          when :UP
            stack.swap(-2, -1)
          # [MOVE LAST (TWO) UP] a1 a2 a3 -- a3 a1 a2
          when :UP2
            stack.swap(-3, -1)
          # a --
          when :POP
            stack.pop
          # ... --
          when :POP_ALL
            stack.clear
          # -- a
          when :SYM
            put var argument
          # -- a
          when :FAST_SYM
            put @context[argument]
          # [fastload SYM in the TOPMOST scope] -- a
          when :FAST_SYM_TOP
            put @context[argument, 0]
          # [SYMBOL OR symbol TO STRING] -- a
          when :SYM_OR_TOS
            put @context.fetch(it = argument) || str it
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
          # ... -- false?
          when :FALSE_IF_EMPTY
            put bool false if stack.empty?
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
          # [TO VECTOR] (a : any) -- (a : vec)
          when :TOV
            put pop.to_vec
          # [TO INVERSE BOOL] (a : any) -- ('a : bool)
          when :TOIB
            put pop.to_bool(inverse: true)
          # [LENGTH] (a : any) -- ('a : num)
          when :LEN
            (it = pop).is_a?(Str | Vec) ? put num it.size : put num it.to_s.size
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
                  when {Str, _}, {Vec, _}
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
          # (a : num) -- (a' : num)
          when :INC
            put num pop.as(Num).value + 1
          # (a : num) (b : num) -- (a' : num)
          when :SUB
            binary(:-)
          # (a : num) -- (a' : num)
          when :DEC
            put num pop.as(Num).value - 1
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

              if amount < 0
                die("'x': negative amount (#{amount})")
              end

              case left
              when Str
                put str left.value * amount
              when Vec
                put vec left.value * amount
              end
            end
          # [ENSURE] a -- a
          when :ENS
            die("ensure: got a falsey value") if tap.false?
          # [GOTO] --
          when :G
            goto! (argument Int32)
          # [GOTO IF TRUE] a --
          when :GIT
            goto! argument Int32 unless pop.false?
          # [GOTO IF FALSE] a --
          when :GIF
            goto! argument Int32 if pop.false?
          # [GOTO IF TRUE POP] a -- a?
          when :GITP
            unless (value = pop).false?
              put value; goto! argument Int32
            end
          # [GOTO IF FALSE POP] a -- a?
          when :GIFP
            if (value = pop).false?
              put value; goto! argument Int32
            end
          # a --
          when :LOCAL
            @context.define(argument, pop)
          # a --
          when :FAST_LOCAL
            @context[argument] = pop
          # a --
          when :GLOBAL
            @context.define(argument, pop, global: true)
          # a -- a
          when :LOCAL_PUT
            @context.define(argument, tap)
          # a -- a
          when :GLOBAL_PUT
            put @context.define(argument, tap, global: true)
          # [REMAINING TO VEC] * -- (a : vec)
          when :REM_TO_VEC
            put vec (pop stack.size, reverse: false)
          # ...types --
          when :FUN
            code = @chunks[argument Int32]
            name = code.name
            given = code.meta.as(FunMeta).given
            types = pop given
            defee = MConcreteFunction.new(types, code)

            case existing = @context.fetch(name)
            when MGenericFunction
              next! existing.add(defee)
            when MFunction
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
              index = -1
              found = false
              count = args.size
              current = callee

              until found
                if callee.is_a?(MGenericFunction)
                  # Break if we're at the end of the variant
                  # list.
                  break if index >= callee.size - 1

                  current = callee[index += 1]
                end

                if current.is_a?(MConcreteFunction)
                  arity = current.arity
                  slurpy = current.slurpy
                  found =
                    ((slurpy && count >= arity) ||
                    (!slurpy && count == arity)) &&
                    typecheck(current.types, args)
                elsif current.is_a?(MBuiltinFunction)
                  arity = current.arity
                  found = count == arity
                end

                # If index is -1 at this point, we're certainly
                # not an MGenericFunction. Thus, if found is false,
                # the function that the user asked for was not
                # found.
                break if index == -1 && !found
              end

              if !found
                die("improper arguments for #{callee}: #{args.join(", ")}")
              elsif current.is_a?(MBuiltinFunction)
                put current.callee.call(self, args)
              elsif current.is_a?(MConcreteFunction)
                invoke!(current.code, args.reverse!)
              end
            else
              die("illegal callee: #{callee}")
            end
          # a --> a
          when :RET
            unless uninvoke(transfer: true)
              die("void functions illegal")
            end
          # a b -- 'a
          when :FIELD
            pop 2 do |head, field|
              if !field.is_a?(Str)
                die("impoper field: #{field}")
              elsif !(value = head.field field.value)
                die("#{head}: no such field: #{field}")
              end

              put value
            end
          when :UPUT
            frame.underscores << pop
          when :UPOP
            if frame.underscores.empty?
              die("void pop from context")
            end

            put frame.underscores.pop
          when :UREF
            if frame.underscores.empty?
              die("void reference to context")
            end

            put frame.underscores.last
          when :SETUP_MAP
            frame.control << tap.as(Vec).size
            frame.control << argument Int32
            frame.control << 0

            put Vec.new
          when :MAP_ITER
            if frame.control[-1] >= frame.control[-3]
              _, stop, _ = frame.control.pop(3)

              goto! stop
            end

            frame.underscores << frame.stack[-2].as(Vec)[frame.@control[-1]]
            frame.control[-1] += 1
          else
            raise InternalError.new("unknown opcode: #{this.opcode}")
          end

          goto
        end

        # Record the current instruction in the timetable.
        if @timetable.has_key?(this.index)
          @timetable[this.index] += took
        else
          @timetable[this.index] = took
        end
      end

      # Print the remnants if the user wished so.
      if remnants
        @frames.each do |frame|
          puts "Remnant frame:", frame
        end
      end
    end

    # Returns the result of this Machine's work.
    def result?
      stack.last?
    end
  end
end
