require "./suite/*"

module Ven
  class Machine
    include Suite

    alias Timetable = Hash(Int32, IStatistics)
    alias IStatistics = Hash(Int32, IStatistic)
    alias IStatistic =
      { amount: Int32,
        duration: Time::Span,
        instruction: Instruction }

    # Fancyline used by the debugger.
    @@fancy = Fancyline.new

    # Whether to run the inspector.
    property inspect : Bool

    # Whether to measure instruction evaluation time.
    property measure : Bool

    getter context : Context::Machine
    getter timetable : Timetable

    @inspect = false
    @measure = false

    # Initializes a Machine given some *chunks*, a *context*
    # and a chunk pointer *cp*: in *chunks*, the chunk at *cp*
    # will be the first to be executed.
    #
    # Remember: per each frame there should always be a scope;
    # if you push a frame, that is, you have to push a scope
    # as well. This has to be done so the frames and the context
    # scopes are in sync.
    def initialize(@context, @chunks : Chunks, cp = 0)
      @frames = [Frame.new(cp: cp)]
      @timetable = Timetable.new
    end

    # Dies of runtime error with *message*, which should explain
    # why the error happened.
    def die(message : String)
      traces = @context.traces.dup

      file = chunk.file
      line = fetch.line

      unless traces.last?.try(&.name) == "unit"
        traces << Trace.new(file, line, "unit")
      end

      raise RuntimeError.new(traces, file, line, message)
    end

    # Builds an `IStatistic` given some *amount*, *duration*
    # and an *instruction*.
    private macro stat(amount, duration, instruction)
      { amount: {{amount}},
        duration: {{duration}},
        instruction: {{instruction}} }
    end

    # Updates the timetable entry for an *instruction* given
    # *duration* - the time it took to execute.
    #
    # *cp* is a chunk pointer to the chunk where the *instruction*
    # is found.
    #
    # *ip* is an instruction pointer to the *instruction*.
    def record!(instruction, duration, cp, ip)
      if !(stats = @timetable[cp]?)
        @timetable[cp] = { ip => stat(1, duration, instruction) }
      elsif !(stat = stats[ip]?)
        stats[ip] = stat(1, duration, instruction)
      else
        stats[ip] = stat(
          stat[:amount] + 1,
          stat[:duration] + duration,
          instruction)
      end
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
      next frame.ip = ({{ip}}.not_nil!)
    end

    # Returns this instruction's jump payload.
    private macro target(source = this)
      chunk.resolve({{source}}).as(VJump).target
    end

    # Returns this instruction's static payload, making sure
    # it is of type *cast*.
    private macro static(cast = String, source = this)
      chunk.resolve({{source}}).as(VStatic).value.as({{cast}})
    end

    # Returns this instruction's symbol payload.
    private macro symbol(source = this)
      chunk.resolve({{source}}).as(VSymbol)
    end

    # Returns this instruction's function payload.
    private macro function(source = this)
      chunk.resolve({{source}}).as(VFunction)
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
    # will pass |x1, x2, x3|.
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
    # child context and starts executing the chunk at *cp*.
    #
    # A trace is made. Trace's filename and line number are
    # figured out automatically, but its *name* must be provided.
    #
    # The new frame's operand stack is initialized with values
    # of *import*. **The order of *import* is kept.**
    #
    # See `Frame::Goal` to see what *goal* is for.
    private macro invoke(name, cp, import values = Models.new, goal = Frame::Goal::Unknown)
      @frames << Frame.new({{goal}}, {{values}}, {{cp}})
      @context.push(chunk.file, fetch.line, {{name}})
    end

    # Reverts the actions of `invoke`.
    #
    # Bool *export* determines whether to put exactly one value
    # from the stack of the invokation onto the parent stack.
    #
    # Returns nil if *export* was requested, but there was no
    # value to export. Returns true otherwise.
    #
    # Pops a scope from the context unless there is but one left.
    private macro revoke(export = false)
      %frame = @frames.pop

      unless @context.size == 1
        @context.pop
      end

      {% if export %}
        if %it = %frame.stack.last?
          put %it

          true
        end
      {% else %}
        true
      {% end %}
    end

    # Looks up the symbol *name* and dies if was not found.
    private macro lookup(name)
      @context[%symbol = {{name}}]? ||
        die("symbol not found: '#{%symbol.name}'")
    end

    # Performs a binary operation on *left*, *right*.
    #
    # Tries to normalize if *left*, *right* cannot be used
    # with the *operator*.
    def binary(operator : String, left : Model, right : Model)
      case {operator, left, right}
      when {"to", Num, Num}
        MRange.new(left, right)
      when {"is", MBool, MBool}
        bool left.eqv?(right)
      when {"is", Str, MRegex}
        may_be str($0), if: left.value =~ right.value
      when {"is", _, MType}
        bool left.of?(right)
      when {"is", _, MAny}
        bool true
      when {"is", _, _}
        # 'is' requires explicit, non-strict (does not die if
        # failed) normalization.
        normal = normalize?(operator, left, right)

        may_be left, if: normal && normal[0].eqv?(normal[1])
      when {"in", Str, Str}
        may_be left, if: right.value.includes?(left.value)
      when {"in", Num, MRange}
        may_be left, if: right.includes?(left.value)
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
        binary operator, *normalize(operator, left, right)
      end
    rescue DivisionByZeroError
      die("'#{operator}': division by zero given #{left}, #{right}")
    end

    # Normalizes a binary operation (i.e., converts it to its
    # normal form).
    #
    # Returns nil if found no matching conversion.
    def normalize?(operator : String, left : Model, right : Model)
      case operator
      when "to"
        return left.to_num, right.to_num
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
        else
          return left, right
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
    end

    # Normalizes a binary operation (i.e., converts it to its
    # normal form).
    #
    # Dies if found no matching conversion.
    def normalize(operator, left, right)
      normalize?(operator, left, right) ||
        die("'#{operator}': could not normalize: #{left}, #{right}")
    end

    # Properly defines a function based off an *informer* and
    # some *given* values.
    def defun(informer : VFunction, given : Models)
      symbol = informer.symbol

      name = symbol.name
      defee = MConcreteFunction.new(name, given,
        informer.arity,
        informer.slurpy,
        informer.params,
        informer.target)

      case existing = @context[symbol]?
      when MGenericFunction
        return existing.add(defee)
      when MFunction
        if existing != defee
          defee = MGenericFunction.new(name)
            .add!(existing)
            .add!(defee)
        end
      end

      @context[symbol] = defee
    end

    # Returns *index*th item of *operand*.
    def nth(operand : Vec, index : Num)
      if operand.length <= index.value
        die("indexable: index out of range: #{index}")
      end

      operand[index.value.to_big_i]
    end

    # :ditto:
    def nth(operand : Str, index : Num)
      if operand.length <= index.value
        die("indexable: index out of range: #{index}")
      end

      operand[index.value.to_big_i]
    end

    # :ditto:
    def nth(operand, index)
      die("value not indexable: #{operand}")
    end

    # Gathers multiple *indices* of an *operand*.
    #
    # Returns a `Vec` of the gathered values.
    def nth(operand : Model, indices : Models)
      vec indices.map { |index| nth(operand, index) }
    end

    # Reduces vector *operand* using a binary *operator*.
    #
    # Note:
    # - If *operand* is empty, returns it back.
    # - If *operand* has one item, returns that one item.
    def reduce(operator : String, operand : Vec)
      case operand.length
      when 0
        operand
      when 1
        operand[0]
      else
        memo = binary(operator, operand[0], operand[1])

        operand[2..].reduce(memo) do |total, current|
          binary(operator, total, current)
        end
      end
    end

    # Reduces range *operand* using a binary *operator*, with
    # some cases not requiring it be computed.
    def reduce(operator, operand : MRange)
      return reduce(operator, operand.to_vec) unless operator == "+"
      # There is only a (fast) formula for sum, it seems.
      num ((operand.start.value + operand.end.value) * operand.length) / 2
    end

    # Fallback reduce (converts *operand* to vec).
    def reduce(operator, operand)
      reduce(operator, operand.to_vec)
    end

    # Resolves a field access.
    #
    # Provides the 'callable?' field for any *head*, which
    # calls `Model.callable?`.
    #
    # If *head* has a field named *field*, returns the value
    # of that field.
    #
    # Otherwise, tries to construct a partial from a function
    # called *field*, if it exists.
    #
    # Returns nil if found no valid field resolution.
    def field?(head : Model, field : Str)
      if field.value == "callable?"
        return bool head.callable?
      end

      head.field(field.value) || field?(head, @context[field.value]?)
    end

    # :ditto:
    def field?(head : Vec, field : MFunction)
      if field.leading?(head)
        return MPartial.new(field, [head.as(Model)])
      end

      result = head.map do |item|
        MPartial.new(field, [item.as(Model)])
      end

      vec result
    end

    # :ditto:
    def field?(head, field : MFunction)
      MPartial.new(field, [head.as(Model)])
    end

    # :ditto:
    def field?(head, field)
      nil
    end

    # If *head*, a vector, has a field *field*, returns the
    # value of that field.
    #
    # Otherwise, spreads the field access on the items of
    # *head*. E.g., `[1, 2, 3].a is [1.a, 2.a, 3.a]`
    def field(head : Vec, field)
      field?(head, field) || vec (head.map { |item| field(item, field) })
    end

    # Same as `field?`, but dies if found no working field
    # resolution.
    def field(head : Model, field : Model)
      field?(head, field) || die("#{head}: no such field or function: #{field}")
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
        when ".f"
          puts frame
        when ".fs"
          @frames.each do |it|
            puts "{\n  #{it}\n}\n"
          end
        when ".c"
          puts control.join(" ")
        when "._"
          puts underscores.join(" ")
        when ".s"
          @context.scopes.each do |scope|
            scope.each do |name, value|
              puts "#{name} = #{value}"
            end

            puts "-" * 32
          end
        when /^(\.h(elp)?|\?)$/
          puts "?  : .h(elp) : display this",
               ".  : display stack",
               ".. : display chunk",
               ".f : display frame",
               ".s : display scopes",
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
      interrupt = false

      # Trap so users see a nice error message instead of
      # just killing the program.
      Signal::INT.trap do
        interrupt = true
      end

      while this = fetch?
        # https://github.com/crystal-lang/crystal/issues/5830#issuecomment-386591044
        sleep 0

        # Remember the chunk we are/(at the end, possibly were)
        # in and the current instruction pointer.
        ip, cp = frame.ip, frame.cp

        begin
          if interrupt
            interrupt = false

            die("interrupted")
          elsif @inspect
            puts "(did) #{this}"
          end

          began = Time.monotonic

          begin
            case this.opcode
            # Pops one value from the stack: (x --)
            in Opcode::POP
              pop
            # Pops two values from the stack (x1 x2 --)
            in Opcode::POP2
              pop 2
            # Swaps two last values on the stack: (x1 x2 -- x2 x1)
            in Opcode::SWAP
              stack.swap(-2, -1)
            # Same as POP, but does not raise on underflow.
            in Opcode::TRY_POP
              stack.pop?
            # Makes a duplicate of the last value: (x1 -- x1 x1')
            in Opcode::DUP
              put tap
            # Clears the stack: (x1 x2 x3 ... --)
            in Opcode::CLEAR
              stack.clear
            # Puts the value of a symbol: (-- x)
            in Opcode::SYM
              put lookup(symbol)
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
            # Puts 'any' onto the stack: (-- any)
            in Opcode::ANY
              put MAny.new
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
            in Opcode::BINARY_ASSIGN
              put binary(static, pop, tap)
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
            # Defines the `*` variable. Pops stack.size - static
            # values.
            in Opcode::REST
              @context["*"] = vec pop(stack.size - static Int32)
            # Defines a function. Requires the values of the
            # given appendix (orelse the appropriate number of
            # `any`s) to be on the stack; it pops them.
            in Opcode::FUN
              defun(myself = function, pop myself.given)
            # If *x1* is a fun/box, invokes it. If a vec/str,
            # indexes it: (x1 a1 a2 a3 ... -- R), where *aN* is
            # an argument, and R is the returned value.
            in Opcode::CALL
              args = pop static(Int32)

              case callee = pop
              when Vec, Str
                put nth(callee, args.size == 1 ? args.first : args)
              when MFunction
                if callee.is_a?(MPartial)
                  # Append the arguments of the call to the
                  # arguments of the partial: partial `1.foo`,
                  # if called like so: `1.foo(2, 3)` - will
                  # after this become `do(1, 2, 3)`.
                  callee, args = callee.function, callee.args + args
                end

                case found = callee.variant?(args)
                when MBox
                  next invoke(callee.to_s, found.target, args)
                when MConcreteFunction
                  next invoke(callee.to_s, found.target, args, Frame::Goal::Function)
                when MBuiltinFunction
                  put found.callee.call(self, args)
                else
                  die("improper arguments for #{callee}: #{args.join(", ")}")
                end
              else
                die("illegal callee: #{callee}")
              end
            # Returns from a function. Puts onto the parent stack
            # the return value defined by the function frame,
            # unless it wasn't specified. In that case, exports
            # the last value from the function frame's operand
            # stack.
            in Opcode::RET
              if returns = frame.returns
                revoke && put returns
              elsif !revoke(export: true)
                die("void expression")
              end
            # Moves a value onto the underscores stack:
            #   oS: (x1 --) ==> _S: (-- x1)
            in Opcode::POP_UPUT
              underscores << pop
            # Copies a value onto the underscores stack:
            #   oS: (x1 -- x1) ==> _S: (-- x1)
            in Opcode::TAP_UPUT
              underscores << tap
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
              length, index, _ = control.last(3)

              if index >= length
                control.pop(3) && jump target
              else
                put tap.as(Vec)[index]
              end

              control[-2] += 1
            # A variation of "&" exclusive to maps. Assumes
            # the last value of the control stack is a stack
            # pointer to the destination vector.
            in Opcode::MAP_APPEND
              stack[control.last].as(Vec) << pop
            # Reduces a vector using a binary operator: ([...] -- x1)
            in Opcode::REDUCE
              put reduce(static, pop)
            # Goes to the chunk it received as the argument.
            in Opcode::GOTO
              next invoke("block", static Int32)
            # Pops an operand and, if possible, gets the value
            # of its field. Alternatively, builds a partial:
            # (x1 -- x2)
            in Opcode::FIELD_IMMEDIATE
              put field(pop, str static)
            # Pops two values, first being the operand and second
            # the field, and, if possible, gets the value of a
            # field. Alternatively, builds a partial: (x1 x2 -- x3)
            in Opcode::FIELD_DYNAMIC
              gather do |head, field|
                put field(head, field)
              end
            # Implements the semantics of 'next fun', which is
            # an explicit tail-call (elimination) request. Pops
            # the callee and N arguments: (x1 ...N --)
            in Opcode::NEXT_FUN
              args = pop static(Int32)
              callee = pop.as(MFunction)

              # Pop frames until we meet the nearest surrounding
              # function. We know there is one because we trust
              # the Compiler.
              @frames.reverse_each do |it|
                next revoke unless it.goal.function?

                variant = callee.variant?(args)

                unless variant.is_a?(MConcreteFunction)
                  die("improper 'next fun': #{callee}: #{args.join(", ")}")
                end

                break revoke &&
                  invoke(variant.to_s, variant.target, args, Frame::Goal::Function)
              end

              next
            # Sets the 'dies' target of this frame. The 'dies'
            # target is jumped to whenever a runtime error
            # occurs.
            in Opcode::SETUP_DIES
              frame.dies = target
            # Resets the 'dies' target of this frame.
            in Opcode::RESET_DIES
              frame.dies = nil
            # Pops a return value and returns out of the nearest
            # surrounding function. Revokes all frames up to &
            # including the frame of that nearest surrounding
            # function. Note that it vetoes `SETUP_RET`: (x1 --)
            in Opcode::FORCE_RET
              value = pop

              @frames.reverse_each do |it|
                revoke

                break put value if it.goal.function?
              end
            # Finds the nearest surrounding function and sets
            # its return value to whatever was tapped. Does
            # not break the flow: (x1 -- x1)
            in Opcode::SETUP_RET
              @frames.reverse_each do |it|
                if it.goal.function?
                  break it.returns = tap
                end
              end
            # Makes a box and puts in onto the stack: (...N) -- B,
            # where N is the number of arguments a box receives
            # and B is the resulting box.
            in Opcode::BOX
              defee = function
              name = defee.symbol.name
              given = pop defee.given

              put MBox.new(
                name, given,
                defee.params,
                defee.arity,
                defee.target
              )
            # Instantiates a box and puts the instance onto the
            # stack: (B -- I), where B is the box parent to this
            # instance, and I is the instance.
            in Opcode::BOX_INSTANCE
              put MBoxInstance.new(pop.as(MFunction), @context.scopes[-1].dup)
            end
          rescue error : ModelCastException | Context::VenAssignmentError
            die(error.message.not_nil!)
          end
        rescue error : RuntimeError
          dies = @frames.reverse_each do |it|
            break it.dies || next revoke
          end

          unless dies
            # Re-raise if climbed up all frames & didn't find
            # a handler.
            raise error
          end

          # I do not know why this is required here, but without
          # it, if interrupted, it rescues infinitely.
          interupt = false

          jump(dies)
        ensure
          if @measure && began
            record!(this, Time.monotonic - began, cp, ip)
          end

          if @inspect
            @inspect = inspector
          end
        end

        jump
      end

      self
    end

    # Cleans up and returns the last value on the operand
    # stack, if any.
    def return!
      @context.clear

      stack.delete_at(..).last?
    end

    # Makes an instance of Machine given *context*, *chunks*
    # and *offset* (see `Machine`). Yields this instance to
    # the block.
    #
    # After the block was executed, starts the Machine and
    # returns the resulting value.
    def self.start(context, chunks, offset)
      machine = new(context, chunks, offset)
      yield machine
      machine.start.return!
    end
  end
end
