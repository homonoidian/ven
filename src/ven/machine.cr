require "./suite/*"

module Ven
  class Machine
    include Suite

    # The timetable consists of chunk identities mapped to hashes
    # of instructions mapped to some `Time::Span`s. Each of these
    # `Time::Span`s is the time it took to execute that particular
    # instruction.
    alias Timetable = Hash(UInt64, Hash(Instruction, Time::Span))

    getter timetable : Timetable

    # Fancyline used by the debugger.
    @@fancy = Fancyline.new

    def initialize(@chunks : Chunks, @context : Context::Machine)
      @frames = [Frame.new]
      @timetable = Timetable.new
    end

    # Dies of runtime error with *message*, which should explain
    # why the error happened.
    def die(message : String)
      raise RuntimeError.new(chunk.file, fetch.line, message)
    end

    # Returns the current frame.
    private macro frame
      @frames.last
    end

    # Returns the current chunk.
    private macro chunk
      @chunks[frame.cp]
    end

    # Returns the current stack.
    private macro stack
      frame.stack
    end

    # Returns the current timetable.
    # private macro timetable
    #   chunk.timetable
    # end

    # Returns the instruction at the IP. Raises if there is
    # no such instruction.
    private macro fetch
      chunk[frame.ip]
    end

    # Returns the instruction at the IP, or nil if there is
    # no such instruction.
    private macro fetch?
      if (%ip = frame.ip) < chunk.size
        chunk[%ip]
      end
    end

    # Goes to the next instruction.
    private macro jump
      frame.ip += 1
    end

    # Jumps to the instruction at some instruction pointer
    # *ip*.
    private macro jump(ip)
      next frame.ip = {{ip}}
    end

    # Resolves the argument of the current instruction. The
    # type of the argument can be ensured by passing *cast*.
    private macro argument(cast = String)
      chunk.resolve(fetch).as({{cast}})
    end

    # Returns *value* if *condition* is true, and *fallback*
    # otherwise.
    private macro may_be(value, if condition, fallback = bool false)
      {{condition}} ? {{value}} : {{fallback}}
    end

    # Puts *value* onto the stack.
    private macro put(value)
      frame.stack << ({{value}})
    end

    # Puts *value* onto the stack if some *condition* is true.
    # Puts `bool` false otherwise.
    private macro put(value, if condition)
      frame.stack << may_be ({{value}}), if: ({{condition}})
    end

    # Puts multiple *values* onto the stack.
    private macro put(*values)
      {% for value in values %}
        put {{value}}
      {% end %}
    end

    # Puts multiple *values* onto the stack if some *condition*
    # is true. Puts `bool` false otherwise.
    private macro put(*values, if condition)
      may_be put *values, if: {{condition}}
    end

    # Returns the last value of the stack. *cast* can be passed
    # to ensure the type of this value. Raises on underflow.
    private macro tap(cast = Model)
      frame.stack.last.as({{cast}})
    end

    # Pops *amount* values from the stack. Keeps their order.
    # *cast* can be passed to ensure the type of each value.
    # Raises on underflow.
    private macro pop(amount = 1, cast = Model)
      {% if amount == 1 %}
        frame.stack.pop.as({{cast}})
      {% elsif cast != Model %}
        frame.stack.pop({{amount}}).map &.as({{cast}})
      {% else %}
        frame.stack.pop({{amount}})
      {% end %}
    end

    # Pops multiple values from the stack and passes them to
    # the block. Keeps their order. The amount of values to
    # pop is determined from the amount of arguments of the
    # block. *cast* can be passed to specify the types of each
    # value (N values, N *cast*s), or all values (N values,
    # 1 *cast*). Raises if *cast* underflows the block arguments.
    private macro get(*cast, &block)
      {% amount = block.args.size %}

      {% unless cast.size == 1 || cast.size == amount %}
        raise "cast underflow"
      {% end %}

      %values = frame.stack.pop({{amount}})

      {% for argument, index in block.args %}
        {% if cast.size == 1 %}
          {% type = cast.first %}
        {% else %}
          {% type = cast[index] %}
        {% end %}

        {{argument}} = %values[{{index}}].as({{type}})
      {% end %}

      {{yield}}
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

    # Performs an invokation: pushes a frame, introduces a
    # child context and starts executing the *chunk*. The
    # frame stack is initialized with values of *import*.
    # Their order is kept.
    private macro invoke(chunk, import values = Models.new)
      @chunks << {{chunk}}
      @frames << Frame.new({{values}}, @chunks.size - 1)
      @context.push
      next
    end

    # Reverts the actions of `invoke`. Bool *export* determines
    # whether to put exactly one value from the stack used by
    # the invokation onto the parent stack. Returns nil if
    # *export* was requested, but there is no value to export.
    private macro revoke(export = false)
      %frame = @frames.pop

      @chunks.pop
      @context.pop

      {% if export %}
        if %it = %frame.stack.last?
          put %it; true
        end
      {% else %}
        true
      {% end %}
    end

    # Matches *args* against *types*. Makes the lattermost
    # type cover the excess arguments, if any. **Will crash
    # of memory error if *types* is empty.**
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

    # Computes a *normal* binary operation. Returns nil if
    # *operator* cannot  accept *left* and *right*.
    def binary(operator : String, left : Model, right : Model)
      case {operator, left, right}
      when {"is", MBool, MBool}
        bool left.eqv?(right)
      when {"is", Str, MRegex}
        may_be str($0), if: left.value =~ right.value
      when {"is", _, MType}
        bool left.of?(right)
      when {"is", _, MAny}
        bool true
      when {"is", _, _}
        may_be left, if: left.eqv?(right)
      when {"in", Str, Str}
        may_be left, if: right.value.includes?(left.value)
      when {"in", _, Vec}
        may_be left, if: right.value.any? &.eqv?(left)
      when {"<", Num, Num}
        bool left.value < right.value
      when {">", Num, Num}
        bool left.value > right.value
      when {"<=", Num, Num}
        bool left.value <= right.value
      when {">=", Num, Num}
        bool left.value >= right.value
      when {"+", Num, Num}
        num left.value + right.value
      when {"-", Num, Num}
        num left.value - right.value
      when {"*", Num, Num}
        num left.value * right.value
      when {"/", Num, Num}
        num left.value / right.value
      when {"&", Vec, Vec}
        vec left.value + right.value
      when {"~", Str, Str}
        str left.value + right.value
      when {"x", Vec, Num}
        vec left.value * right.value.to_big_i
      when {"x", Str, Num}
        str left.value * right.value.to_big_i
      end
    rescue DivisionByZeroError
      die("'#{operator}': division by zero given #{left}, #{right}")
    end

    # Normalizes (i.e., converts to the *normal* form) a binary
    # operation. Dies if failed to convert, or if found no
    # matching conversion template.
    def normalize(operator : String, left : Model, right : Model)
      begin
        case operator
        when "is" then case {left, right}
          when {_, MRegex}
            return left.to_str, right
          when {MRegex, _}
            return right.to_str, left
          when {_, Str}, {Str, _}
            return left.to_str, right.to_str
          when {_, Vec}, {Vec, _}
            return left.to_vec, right.to_vec
          when {_, Num}, {Num, _}
            return left.to_num, right.to_num
          when {_, MBool}, {MBool, _}
            return left.to_bool, right.to_bool
          end
        when "x" then case {left, right}
          when {_, Vec}, {_, Str}
            return right, left.to_num
          when {Str, _}, {Vec, _}
            return left, right.to_num
          else
            return left.to_vec, right.to_num
          end
        when "in" then case {left, right}
          when {_, Str}, {Str, _}
            return left.to_str, right.to_str
          end
        when "<", ">", "<=", ">="
          return left.to_num, right.to_num
        when "+", "-", "*", "/"
          return left.to_num, right.to_num
        when "~"
          return left.to_str, right.to_str
        when "&"
          return left.to_vec, right.to_vec
        end
      rescue ModelCastException
        # (fallthrough)
      end

      die("'#{operator}': could not normalize: #{left}, #{right}")
    end

    # Interprets a debugger *command*, with the current
    # instruction being *instruction*.
    def debug(command : String, instruction : Instruction)
      if command.in?(".", ".i", ".instruction")
        puts chunk.to_s(instruction)
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
        puts @context[command]? || "no such variable: #{command}"
      end
    end

    # >>>>>>>>>>>>> BADLANDS start <<<<<<<<<<<<<

    # Starts the evaluation loop, which begins to fetch the
    # instructions from the current chunk and execute them,
    # until there aren't any left. *debug*, if true, enables
    # state inspection following every fetch.
    def start(debug = false)
      remnants = false

      while this = fetch?
        if debug
          begin
            puts "Hit CTRL+C to step, or CTRL+D to skip all"

            loop do
              unless command = @@fancy.readline("#{frame.ip}, in #{chunk.name} >>> ")
                remnants = @@fancy.readline("Print remnant frames? (y/n) ") == "y"

                # EOF goes out of debug mode.
                break debug = false
              end

              debug(command, this.as Instruction)
            end
          rescue Fancyline::Interrupt
            puts
          end
        end

        time = Time.measure do
          case this.opcode
          # Pops one value from the stack: (x --)
          when :POP
            pop
          # Makes a duplicate of the last value: (x1 -- x1 x2)
          when :DUP
            put tap
          # Clears the stack: (x1 x2 x3 ... --)
          when :CLEAR
            stack.clear
          # XXX: rewrite
          when :SYM
            put @context[argument(Entry)]
          # -- (a : num)
          when :NUM
            put num argument(BigDecimal)
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
          when :BINARY
            get(Model) do |left, right|
              operator = argument

              until result = binary(operator, left, right)
                left, right = normalize(operator, left, right)
              end

              put result
            end
          # [ENSURE] a -- a
          when :ENS
            die("ensure: got a falsey value") if tap.false?
          # [GOTO] --
          when :G
            jump (argument Int32)
          # [GOTO IF TRUE] a --
          when :GIT
            jump (argument Int32) unless pop.false?
          # [GOTO IF FALSE] a --
          when :GIF
            jump (argument Int32) if pop.false?
          # [GOTO IF TRUE POP] a -- a?
          when :GITP
            unless (value = pop).false?
              put value

              jump (argument Int32)
            end
          # [GOTO IF FALSE POP] a -- a?
          when :GIFP
            if (value = pop).false?
              put value

              jump (argument Int32)
            end
          # a --
          when :SET_POP
            @context[argument(Entry)] = pop
          # a -- a
          when :SET_TAP
            @context[argument(Entry)] = tap
          # [REMAINING TO VEC] * -- (a : vec)
          when :REM_TO_VEC
            put vec (pop stack.size)
          # ...types --
          when :FUN
            code = @chunks[argument Int32]
            name = code.name
            given = code.meta.as(Metadata::Function).given
            types = pop given
            defee = MConcreteFunction.new(types, code)

            case existing = @context[name]?
            when MGenericFunction
               existing.add(defee)
            when MFunction
              if existing != defee
                @context[name] = MGenericFunction
                  .new(name)
                  .add!(existing)
                  .add!(defee)
              end
            else
              @context[name] = defee
            end
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
                invoke(current.code, args.reverse!)
              end
            else
              die("illegal callee: #{callee}")
            end
          # a --> a
          when :RET
            unless revoke(export: true)
              die("void functions illegal")
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

              jump stop
            end

            frame.underscores << frame.stack[-2].as(Vec)[frame.@control[-1]]
            frame.control[-1] += 1
          else
            raise InternalError.new("unknown opcode: #{this.opcode}")
          end

          jump
        end

        # Record the current instruction in the timetable.
        if @timetable.dig?(c_id = chunk.hash, this)
          @timetable[c_id][this] += time
        elsif it = @timetable[c_id]?
          it[this] = time
        else
          @timetable[c_id] = { this => time }
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
