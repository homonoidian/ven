require "./suite/*"

module Ven
  class Machine
    include Suite

    # Fancyline used by the debugger.
    @@fancy = Fancyline.new

    property inspect : Bool
    property measure : Bool

    @inspect = false
    @measure = false

    def initialize(@chunks : Chunks, @context : Context::Machine)
      @frames = [Frame.new]
    end

    # Dies of runtime error with *message*, which should explain
    # why the error happened.
    def die(message : String)
      raise RuntimeError.new(chunk.file, fetch.line, message)
    end

    # Records an *instruction* in the timetable.
    #
    # The timetable records the duration and the amount of
    # evaluations of an instruction pointer.
    #
    # Returns true.
    def record!(cp : Int32, ip : Int32, instruction : Instruction, duration : Time::Span)
      unless entry = @timetable[cp]?
        @timetable[cp] = TEntry.new
      end

      unless statistic = @timetable[cp][ip]?
        @timetable[cp][ip] =
          { amount: 1,
            duration: duration,
            instruction: instruction }
      else
        @timetable[cp][ip] =
          { amount: statistic[:amount] + 1,
            duration: statistic[:duration] + duration,
            instruction: instruction }
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

    # Jumps to the next instruction.
    private macro jump
      frame.ip += 1
    end

    # Jumps to the instruction at some instruction pointer *ip*.
    private macro jump(ip)
      next frame.ip = {{ip}}
    end

    # Returns this instruction's jump payload.
    private macro target
      chunk.resolve(fetch).as(VJump).target
    end

    # Returns this instruction's static payload, making sure
    # it is of type *cast*.
    private macro static(cast = String)
      chunk.resolve(fetch).as(VStatic).value.as({{cast}})
    end

    # Returns this instruction's symbol payload.
    private macro symbol
      chunk.resolve(fetch).as(VSymbol)
    end

    # Returns this instruction's function payload.
    private macro function
      chunk.resolve(fetch).as(VFunction)
    end

    # Interprets this instruction's static payload as an
    # offset of a chunk. Returns that chunk.
    private macro chunk_argument
      @chunks[static(Int32)]
    end

    # Returns *value* if *condition* is true, and *fallback*
    # if it isn't.
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

            # 'next' vetoes 'return' once, as `normalize`
            # raises if unable to normalize.
            next
          end
      end
    rescue DivisionByZeroError
      die("'#{operator}': division by zero given #{left}, #{right}")
    end

    # Normalizes a binary operation (i.e., converts it to its
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
    def defun(informer : VFunction, given : Models)
      name = informer.name
      chunk = @chunks[informer.target]
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
        # function that the user asked for was not and could
        # not be found.
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

    # Gathers several *indexes* for *indexee* and returns
    # a `Vec` of them.
    def nth(indexee : Model, indexes : Models)
      vec indexes.map { |index| nth(indexee, index) }
    end

    # Reduces *reducee* using a binary *operator*.
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

        case got = got.try(&.strip)
        when "."
          puts stack.join(" ")
        when ".."
          puts chunk
        when ".c"
          puts control.join(" ")
        when "._"
          puts underscores.join(" ")
        when /^(\.h(elp)?|\?)$/
          puts "?  : .h(elp) : display this",
               ".  : display stack",
               ".. : display chunk",
               ".c : display control",
               "._ : display underscores",
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
        if @inspect
          puts this
        end

        case this.opcode
        # Pops one value from the stack: (x --)
        in Opcode::POP
          pop
        # Pops two values from the stack (x1 x2 --)
        in Opcode::POP2
          pop 2
        # Same as POP, but does not raise on underflow.
        in Opcode::TRY_POP
          frame.stack.pop?
        # Makes a duplicate of the last value: (x1 -- x1 x1')
        in Opcode::DUP
          put tap
        # Clears the stack: (x1 x2 x3 ... --)
        in Opcode::CLEAR
          stack.clear
        # Puts the value of a symbol: (-- x)
        in Opcode::SYM
          put @context[symbol]
        # Puts a number: (-- x)
        in Opcode::NUM
          put num static(BigDecimal)
        # Puts a string: (-- x)
        in Opcode::STR
          put str static
        # Puts a regex: (-- x)
        in Opcode::PCRE
          put regex static
        # Joins multiple values under a vector: (x1 x2 x3 -- [x1 x2 x3])
        in Opcode::VEC
          put vec pop static(Int32)
        # Puts true: (-- true)
        in Opcode::TRUE
          put bool true
        # Puts false: (-- false)
        in Opcode::FALSE
          put bool false
        # Puts false if stack is empty:
        #  - (-- false)
        #  - (... -- ...)
        in Opcode::FALSE_IF_EMPTY
          put bool false if stack.empty?
        # Negates a num: (x1 -- -x1)
        in Opcode::NEG
          put pop.to_num.neg!
        # Converts to num: (x1 -- x1' : num)
        in Opcode::TON
          put pop.to_num
        # Converts to str: (x1 -- x1' : str)
        in Opcode::TOS
          put pop.to_str
        # Converts to bool: (x1 -- x1' : bool)
        in Opcode::TOB
          put pop.to_bool
        # Converts to inverse boolean (...#t, ...#f - true/false
        # by meaning):
        #   - (x1#t -- false)
        #   - (x1#f -- true)
        in Opcode::TOIB
          put pop.to_bool(inverse: true)
        # Converts to vec (unless vec):
        #   - (x1 -- [x1])
        #   - ([x1] -- [x1])
        in Opcode::TOV
          put pop.to_vec
        # Puts length of an entity: (x1 -- x2)
        in Opcode::LEN
          put num pop.length
        # Evaluates a binary operation: (x1 x2 -- x3)
        in Opcode::BINARY
          gather { |lhs, rhs| put binary(static, lhs, rhs) }
        # Dies if tap is false: (x1 -- x1)
        in Opcode::ENS
          die("ensure: got false") if tap.false?
        # Jumps at some instruction pointer.
        in Opcode::J
          jump target
        # Jumps at some instruction pointer if not popped
        # bool false: (x1 --)
        in Opcode::JIT
          jump target unless pop.false?
        # Jumps at some instruction pointer if popped bool
        # false: (x1 --)
        in Opcode::JIF
          jump target if pop.false?
        # Jumps at some instruction pointer if not tapped
        # bool false; pops otherwise:
        #   - (true -- true)
        #   - (false --)
        in Opcode::JIT_ELSE_POP
          tap.false? ? pop : jump target
        # Jumps at some instruction pointer if tapped bool
        # false; pops otherwise:
        #   - (true --)
        #   - (false -- false)
        in Opcode::JIF_ELSE_POP
          tap.false? ? jump target : pop
        # Pops and assigns it to a symbol: (x1 --)
        in Opcode::POP_ASSIGN
          @context[symbol] = pop
        # Taps and assigns it to a symbol: (x1 -- x1)
        in Opcode::TAP_ASSIGN
          @context[symbol] = tap
        # Pops and adds one. Raises if not a number: (x1 -- x1)
        in Opcode::INC
          put num pop.as(Num).value + 1
        # Pops and subtracts one. Raises if not a number:
        # (x1 -- x1)
        in Opcode::DEC
          put num pop.as(Num).value - 1
        # Converts the stack into a vector: (... -- [...])
        in Opcode::REM_TO_VEC
          put vec pop(stack.size)
        # Defines a function. Requires the values of the
        # given appendix (orelse the appropriate number of
        # `any`s) to be on the stack; it pops them.
        in Opcode::FUN
          defun(myself = function, pop myself.given)
        # If *x1* is a fun, invokes it. If a vec/str, indexes
        # it: (x1 a1 a2 a3 ... -- R), where *aN* is an argument,
        # and R is the returned value.
        in Opcode::CALL
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
        # Returns from a function. Exports last value from
        # the function's stack beforehand.
        in Opcode::RET
          unless revoke(export: true)
            die("void expression")
          end
        # Moves a value onto the underscores stack:
        #   S: (x1 --) ==> _: (-- x1)
        in Opcode::UPUT
          underscores << pop
        # Moves a value from the underscores stack:
        in Opcode::UPOP
          put underscores.pop? || die("'_': no contextual")
        # Moves a copy of a value from the underscores stack
        # to the stack:
        in Opcode::UREF
          put underscores.last? || die("'&_': no contextual")
        # Prepares for a series of `MAP_ITER`s on a vector.
        in Opcode::MAP_SETUP
          control << tap.length << 0 << stack.size - 2
        # Executed each map iteration. It assumes:
        #   - that control[-2] is the index, and
        #   - control[-3] is the length of the vector we
        #   iterate on;
        in Opcode::MAP_ITER
          if control[-2] >= control[-3]
            control.pop(3) && jump target
          end

          control[-2] += 1
        # A variation of "&" exclusive to maps. Assumes
        # the last value of the control stack is a stack
        # pointer to the destination vector.
        in Opcode::MAP_APPEND
          stack[control.last].as(Vec) << pop
        # Reduces a vector using a binary operator: ([...] -- x1)
        in Opcode::REDUCE
          put reduce(static, pop.as Vec)
        # Goes to the chunk it received as the argument.
        in Opcode::GOTO
          invoke(chunk_argument)
        end

        if @inspect
          @inspect = inspector
        end

        jump
      end
    end

    # Returns the result of this Machine's work.
    def result?
      stack.last?
    end
  end
end
