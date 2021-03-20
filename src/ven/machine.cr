require "./suite/*"

module Ven
  class Machine
    include Suite

    # Fancyline used by the debugger.
    @@fancy = Fancyline.new

    alias Timetable = Hash(UInt64, Hash(Instruction, IData))
    alias IData = {Int32, Time::Span}

    getter timetable : Timetable

    property inspect : Bool
    property measure : Bool

    @inspect = false
    @measure = false

    def initialize(@chunks : Chunks, @context : Context::Machine)
      @frames = [Frame.new]
      @timetable = Timetable.new
    end

    # Dies of runtime error with *message*, which should explain
    # why the error happened.
    def die(message : String)
      raise RuntimeError.new(chunk.file, fetch.line, message)
    end

    # Records the *instruction* in the timetable.
    #
    # Returns true.
    def record!(instruction : Instruction, duration : Time::Span)
      id = chunk.hash

      if !@timetable[id]?
        @timetable[id] = {} of Instruction => IData
      end

      if !@timetable[id][instruction]?
        @timetable[id][instruction] = { 1, duration }
      else
        existing = @timetable[id][instruction]

        @timetable[id][instruction] = {
          existing[0] + 1,
          existing[1] + duration
        }
      end

      true
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

    # Returns the current control stack.
    private macro control
      frame.control
    end

    # Returns the current underscores stack.
    private macro underscores
      frame.underscores
    end

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

    # Jumps to the instruction at some instruction pointer *ip*.
    private macro jump(ip)
      next frame.ip = {{ip}}
    end

    # Resolves the argument of the current instruction, assuming
    # it is a jump to some instruction pointer (`DJump`).
    private macro anchor
      chunk.resolve(fetch, :jump).as(DJump).anchor
    end

    # Resolves the argument of the current instruction, assuming
    # it is a static value of type *cast* (`DStatic`).
    private macro static(cast = String)
      chunk.resolve(fetch, :static).as({{cast}})
    end

    # Resolves the argument of the current instruction, assuming
    # it is a symbol (`DSymbol`).
    private macro symbol
      chunk.resolve(fetch, :symbol).as(DSymbol)
    end

    # Resolves the argument of the current instruction, assuming
    # it is a function (`DFunction`).
    private macro function
      chunk.resolve(fetch, :function).as(DFunction)
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
    # to ensure the type of the value. Raises on underflow.
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
    # the block, keeping their order. E.g., given (x1 x2 x3 --),
    # will pass |x1, x2, x3|, not |x3, x2, x1|.
    #
    # The amount of values to pop is determined from the amount
    # of block's arguments.
    #
    # *cast* can be passed to specify the types of each value
    # (N values, N *cast*s), or all values (N values, 1 *cast*).
    # *cast* defaults to `Model`, and thus can be omitted.
    #
    # Raises if *cast* underflows the block arguments.
    private macro gather(cast = {Model}, &block)
      {% amount = block.args.size %}

      {% if cast.size != 1 && cast.size != amount %}
        {{raise "cast underflow"}}
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
    # **The order of *import* is kept.**
    private macro invoke(chunk, import values = Models.new)
      @chunks << {{chunk}}
      @frames << Frame.new({{values}}, @chunks.size - 1)
      @context.push
      next
    end

    # Reverts the actions of `invoke`.
    #
    # Bool *export* determines whether to put exactly one value
    # from the stack of the invokation onto the parent stack.
    #
    # Returns nil if *export* was requested, but there was no
    # value to export. Returns true otherwise.
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

    # Matches *args* against *types*.
    #
    # Makes the lattermost type cover the excess arguments,
    # if any.
    #
    # NOTE: will crash of memory error if *types* is empty.
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

    # Performs a binary operation on *left*, *right*.
    #
    # Tries to normalize if *left*, *right* cannot be used
    # with the *operator*.
    def binary(operator : String, left : Model, right : Model)
      loop do
        return case {operator, left, right}
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
          else
            left, right = normalize(operator, left, right)

            # 'next' vetoes 'return'. Also, `normalize` raises
            # if unable to normalize. Hence not an infinite
            # loop.
            next
          end
      end
    rescue DivisionByZeroError
      die("'#{operator}': division by zero given #{left}, #{right}")
    end

    # Normalizes a binary operation (i.e., converts to its
    # normal form, if any).
    #
    # Dies if could not convert, or if found no matching
    # conversion.
    def normalize(operator : String, left : Model, right : Model)
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

      die("'#{operator}': could not normalize: #{left}, #{right}")
    rescue e : ModelCastException
      die("'#{operator}': #{e.message}: #{left}, #{right}")
    end

    # Properly defines a function based off an *informer* and
    # some *given* values.
    def defun(informer : DFunction, given : Models)
      name = informer.name
      chunk = @chunks[informer.chunk]
      defee = MConcreteFunction.new(name,
        informer.arity,
        informer.slurpy,
        informer.params,
        given, chunk)

      case existing = @context[name]?
      when MGenericFunction
        return existing.add(defee)
      when MFunction
        if existing != defee
          defee = MGenericFunction.new(name)
            .add!(existing)
            .add!(defee)
        end
      end

      @context[name] = defee
    end

    # Returns the variant of *callee* that understands *args*,
    # or false if such variant wasn't found.
    def variant?(callee : MFunction, args : Models)
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
            typecheck(current.given, args)
        elsif current.is_a?(MBuiltinFunction)
          arity = current.arity
          found = count == arity
        end

        # If at this point index is -1, we're certainly not
        # an MGenericFunction. Thus, if found is false, the
        # function that the user asked for was not found.
        # Break if so.
        break if index == -1 && !found
      end

      found && current
    end

    # Returns *index*th item of *indexee*.
    def nth(indexee : Vec, index : Num)
      if indexee.length <= index.value
        die("index out of range: #{index}")
      end

      indexee[index.value.to_big_i]
    end

    # :ditto:
    def nth(indexee : Str, index : Num)
      if indexee.length <= index.value
        die("index out of range: #{index}")
      end

      indexee[index.value.to_big_i]
    end

    # :ditto:
    def nth(indexee, index)
      die("indexee not indexable: #{indexee}")
    end

    # Gathers multiple *indexes* for *indexee* and returns
    # a `Vec` of them.
    def nth(indexee : Model, indexes : Models)
      vec indexes.map { |index| nth(indexee, index) }
    end

    # Reduces the *reducee* using a binary *operator*.
    def reduce(operator : String, reducee : Vec)
      case reducee.length
      when 0
        reducee
      when 1
        reducee[0]
      else
        memo = binary(operator, reducee[0], reducee[1])

        reducee[2..].reduce(memo) do |total, current|
          binary(operator, total, current)
        end
      end
    end

    # Starts a primitive state inspector prompt.
    #
    # Returns false if the user wanted to terminate inspector
    # functionality, or true if the user requested the next
    # instruction.
    def inspector
      loop do
        begin
          got = @@fancy.readline("#{frame.ip}@#{chunk.name} :: ")
        rescue Fancyline::Interrupt # CTRL-C
          puts

          return true
        end

        case got
        when /^\./
          puts stack.join(" ")
        when /^\.\./
          puts "#{chunk.dis(point_at: frame.ip)}"
        when /^\.c/
          puts control.join(" ")
        when /^\._/
          puts underscores.join(" ")
        when /^\.n(ext)?/
          puts fetch? || "nothing"
        when /^\.h(elp)?|^\?/
          puts "?  : .h(elp) : display this",
               ".  : display stack",
               ".. : display chunk",
               ".c : display control",
               "._ : display underscores",
               ".n(ext) displays the following instruction",
               "CTRL-C : step",
               "CTRL-D : skip all"
        when nil # EOF (CTRL-D)
          return false
        else
          puts @context[got]? || "variable not found: #{got}"
        end
      end
    end

    # Starts the evaluation loop, which begins to fetch the
    # instructions from the current chunk and execute them,
    # until there aren't any left.
    def start
      while this = fetch?
        puts chunk.dis(this) if @inspect

        duration = Time.measure do
          case this.opcode
          # Pops one value from the stack: (x --)
          when :POP
            pop
          # Makes a duplicate of the last value: (x1 -- x1 x1')
          when :DUP
            put tap
          # Clears the stack: (x1 x2 x3 ... --)
          when :CLEAR
            stack.clear
          # Puts the value of a symbol: (-- x)
          when :SYM
            put @context[symbol]
          # Puts a number: (-- x)
          when :NUM
            put num static(BigDecimal)
          # Puts a string: (-- x)
          when :STR
            put str static
          # Puts a regex: (-- x)
          when :PCRE
            put regex static
          # Joins multiple values under a vector: (x1 x2 x3 -- [x1 x2 x3])
          when :VEC
            put vec pop static(Int32)
          # Puts true: (-- true)
          when :TRUE
            put bool true
          # Puts false: (-- false)
          when :FALSE
            put bool false
          # Puts false if stack is empty:
          #  - (-- false)
          #  - (... -- ...)
          when :FALSE_IF_EMPTY
            put bool false if stack.empty?
          # Negates a num: (x1 -- -x1)
          when :NEG
            put pop.to_num.neg!
          # Converts to num: (x1 -- x1' : num)
          when :TON
            put pop.to_num
          # Converts to str: (x1 -- x1' : str)
          when :TOS
            put pop.to_str
          # Converts to bool: (x1 -- x1' : bool)
          when :TOB
            put pop.to_bool
          # Converts to inverse boolean:
          #   - (x1#t -- false)
          #   - (x1#f -- true)
          when :TOIB
            put pop.to_bool(inverse: true)
          # Converts to vec (unless vec):
          #   - (x1 -- [x1])
          #   - ([x1] -- [x1])
          when :TOV
            put pop.to_vec
          # Puts length of an entity: (x1 -- x2)
          when :LEN
            put num pop.length
          # Evaluates a binary operation: (x1 x2 -- x3)
          when :BINARY
            gather { |lhs, rhs| put binary(static, lhs, rhs) }
          # Dies if tap is false: (x1 -- x1)
          when :ENS
            die("ensure: got false") if tap.false?
          # Jumps at some instruction pointer.
          when :J
            jump anchor
          # Jumps at some instruction pointer if popped true:
          # (x1 --)
          when :JIT
            jump anchor unless pop.false?
          # Jumps at some instruction pointer if popped false:
          # (x1 --)
          when :JIF
            jump anchor if pop.false?
          # Jumps at some instruction pointer if tapped true;
          # pops otherwise:
          #   - (true -- true)
          #   - (false --)
          when :JIT_ELSE_POP
            tap.false? ? pop : jump anchor
          # Jumps at some instruction pointer if tapped false;
          # pops otherwise:
          #   - (true --)
          #   - (false -- false)
          when :JIF_ELSE_POP
            tap.false? ? jump anchor : pop
          # Pops and assigns it to a symbol: (x1 --)
          when :POP_ASSIGN
            @context[symbol] = pop
          # Taps and assigns it to a symbol: (x1 -- x1)
          when :TAP_ASSIGN
            @context[symbol] = tap
          # Makes whole stack a vector: (... -- [...])
          when :REM_TO_VEC
            put vec pop(stack.size)
          # Defines a function. Requires the values of the
          # given appendix to be on the stack; it pops them.
          when :FUN
            defun(myself = function, pop myself.given)
          # If *x1* is a fun, invokes it. If a vec/str, indexes
          # it: (x1 a1 a2 a3 -- R), where *aN* is an argument,
          # and R is the returned value.
          when :CALL
            args = pop static(Int32)

            case callee = pop
            when Vec, Str
              put nth(callee, args.size == 1 ? args.first : args)
            when MFunction
              found = variant?(callee, args)

              if found.is_a?(MConcreteFunction)
                invoke(found.code, args.reverse!)
              elsif found.is_a?(MBuiltinFunction)
                put found.callee.call(self, args)
              else
                die("improper arguments for #{callee}: #{args.join(", ")}")
              end
            else
              die("illegal callee: #{callee}")
            end
          # Returns from a function. Exports exactly one last
          # value from the function's stack.
          when :RET
            unless revoke(export: true)
              die("void functions illegal")
            end
          # Brings a value to the underscores stack:
          #   S: (x1 --) ==> _: (-- x1)
          when :UPUT
            underscores << pop
          # Brings a value from the underscores stack:
          when :UPOP
            put underscores.pop? || die("'_': no contextual")
          # Brings a copy of a value from the underscores stack:
          when :UREF
            put underscores.last? || die("'&_': no contextual")
          # Prepares for a series of `MAP_ITER`s on a vector.
          when :MAP_SETUP
            control << tap.length << 0 << stack.size - 2
          # It is executed each map iteration. Assumes:
          #   - that control[-2] is the index, and
          #   - control[-3] is the length of the iteratee;
          when :MAP_ITER
            if control[-2] >= control[-3]
              control.pop(3) && jump anchor
            end

            control[-2] += 1
          # A variation of "&" exclusive to maps. Assumes
          # the last value of the control stack is a stack
          # pointer to the destination vector.
          when :MAP_APPEND
            stack[control.last].as(Vec) << pop
          # Reduces a vector using a binary operator: ([...] -- x1)
          when :REDUCE
            put reduce(static, pop.as Vec)
          else
            raise InternalError.new("unknown opcode: #{this.opcode}")
          end

          jump
        end

        if @measure
          record!(this, duration)
        end

        if @inspect
          @inspect = inspector
        end
      end
    end

    # Returns the result of this Machine's work.
    def result?
      stack.last?
    end
  end
end
