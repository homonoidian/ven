require "fancyline"
require "./suite/*"

module Ven
  class Machine
    include Suite

    alias Timetable = Hash(Int32, IStatistics)
    alias IStatistics = Hash(Int32, IStatistic)
    alias IStatistic = {amount: Int32, duration: Time::Span, instruction: Instruction}

    # How many interpreter loop ticks to wait before Ven
    # scheduling logic gives way to the other, enqueued
    # fibers.
    SCHEDULER_TICK_PERIOD = 10

    # Fancyline used by the debugger.
    @@fancy = Fancyline.new

    # Returns the chunks this machine has knowledge of.
    getter chunks : Chunks
    # Returns the context of this machine.
    getter context : CxMachine

    # Returns the `Enquiry` object this machine writes to
    # and reads from.
    property enquiry : Enquiry

    @timetable : Timetable

    # Makes a new `Machine` that will run *chunks*, starting
    # with the chunk at *origin* (the origin chunk).
    def initialize(@chunks, @context = CxMachine.new, origin = 0, @enquiry = Enquiry.new, frames : Array(Frame)? = nil)
      @frames = frames ? frames.not_nil! : [Frame.new(cp: origin)]
      @inspect = @enquiry.inspect.as Bool
      @measure = @enquiry.measure.as Bool
      @timetable = @enquiry.timetable = Timetable.new
    end

    # Dies of runtime error with *message*, which should explain
    # why the error happened.
    def die(message : String)
      file = chunk.file
      line = fetch.line

      traces = @frames.select(&.trace).map(&.trace.not_nil!)
      traces << Trace.new(file, line, "unit")

      raise RuntimeError.new(traces.uniq, file, line, message)
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
        @timetable[cp] = {ip => stat(1, duration, instruction)}
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
      @frames[-1]
    end

    # Yields the closest frame with goal set to *goal*.
    private macro frame(goal, &block)
      @frames.reverse_each do |%frame|
        if %frame.goal == {{goal}}
          {{*block.args}} = %frame
          {{yield}}
          break
        end
      end
    end

    # Same as `frame(goal, &block)`, but destructive (via
    # `revoke`) to all frames visited before the one with
    # the matching goal, and to the frame with the matching
    # goal itself.
    #
    # If did not find a frame with the matching goal, **all**
    # frames are destroyed.
    private macro rewind(goal, &block)
      @frames.reverse_each do |%frame|
        revoke
        if %frame.goal == {{goal}}
          {{*block.args}} = %frame
          {{yield}}
          break
        end
      end
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

    # Immediately Jumps to the instruction at *ip*.
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
      frame.stack[-1].as({{cast}})
    end

    # Pops *amount* values from the stack. Keeps their order.
    # *cast* can be passed to ensure the type of each value.
    # Raises on underflow.
    private macro pop(amount = 1, as cast = Model)
      {% if amount == 1 %}
        frame.stack.pop.as({{cast}})
      {% elsif cast != Model %}
        frame.stack.pop({{amount}}).map &.as({{cast}})
      {% else %}
        frame.stack.pop({{amount}})
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

    # Initiates invokation: does `Context#push`, and appends
    # a function invokation frame to `@frames`.
    #
    # The frame's trace's description is set to *desc* if
    # it is provided.
    #
    # The frame's stack will be initialized with *initial*
    # values (with their order kept).
    #
    # See `Frame::Goal` to learn about *goal*.
    private macro invoke(origin, desc = nil, initial = Models.new, goal = Frame::Goal::Function)
      @context.push
      @frames << Frame.new(
        {{goal}},
        {{initial}},
        {{origin}},
        {% if desc %}
          trace: Trace.new(chunk.file, fetch.line, {{desc}}),
        {% end %}
      )
    end

    # Performs invokation teardown.
    #
    # If *export* is true, requests a return value from
    # the invokation. Returns the value if that request
    # was fulfilled, otherwise nil.
    private macro revoke(export = false)
      @context.pop

      %frame = @frames.pop

      {% if export %}
        (%return = %frame.stack.last?) && put %return
      {% else %}
        true
      {% end %}
    end

    # Looks up a `VSymbol` *symbol* and dies if it was not found.
    private macro lookup(symbol)
      @context[%it = {{symbol}}]? || die("symbol not found: #{%it.name}")
    end

    # Searches for a hook function and evaluates it.
    #
    # A hook function is a function implemented in Ven and
    # called by the interpreter to perform a particular task
    # (which might be near to impossible to perform by Machine's
    # means).
    private macro hook(name, args)
      if !(%callee = @context[%name = {{name}}]?)
        die("hook '#{%name}' not found")
      elsif !%callee.is_a?(MFunction)
        die("hook '#{%name}' is not a function")
      end

      %variant = %callee.variant?(%args = {{args}})

      unless %variant.is_a?(MConcreteFunction)
        die("argument/parameter mismatch: #{%args.join(", ")}")
      end

      invoke(%variant.target, %variant.to_s, %args)
    end

    # Looks up for an underscores value in the frames above
    # the current; depending on *pop*, will either return it,
    # or pop it in the appropriate frame and return it.
    #
    # Returns nil if no underscores value was found.
    private macro u_lookup(pop = true)
      @frames.reverse_each do |above|
        if {% if pop %}
              (%it = above.underscores.pop?)
           {% else %}
              (%it = above.underscores.last?)
           {% end %}
          break %it
        end
      end
    end

    # Assigns `VSymbol` *target* to *value*.
    #
    # If *value* is a lambda, does `MLambda#myself=` with
    # *target*.
    #
    # Returns *value*.
    private macro assign(target, value)
      %target = {{target}}.as(VSymbol)
      %value  = {{value}}

      # A snippet of slapcode to make lambdas recursive.
      #
      # Lambda assignment happens outside of lambda's isolated
      # scope, so it has no access to itself. Let it have one.
      #
      # The 'myself=' assignment should happen only once, so
      # this snippet:
      #
      # ```ven
      # x = (a) [x, y];
      # y = x;
      # y();
      # ```
      #
      # Will die because 'y' is not defined inside the lambda
      # (while 'x' is).
      if %value.is_a?(MLambda)
        %value.myself = %target.name
      end

      @context[%target] = %value
    end

    # Performs a binary operation on *left*, *right*.
    #
    # Tries to normalize if *left*, *right* cannot be used
    # with the *operator*.
    def binary(operator : String, left : Model, right : Model)
      case {operator, left, right}
      when {"to", Num, Num}
        MFullRange.new(left, right)
      when {"is", Str, MRegex}
        # `str is regex` does not return *left*, but instead
        # full match result (or false if there isn't any).
        #
        # Also, if there are named groups in the regex, the
        # matches for those named groups are bound in the
        # current scope under the corresponding names, unless
        # one of them conflicts with an existing symbol.
        if match = right.regex.match(left.value)
          match.named_captures.each do |capture, value|
            if @context[capture]?
              die("capture in conflict with an existing symbol: #{capture}")
            end
            @context[capture] = value ? str(value) : bool false
          end
          return str(match[0])
        end
        bool false
      when {"is", MBool, _}
        # This makes clauses like `false is false` work. The
        # following machinery will cause these to return the
        # left `false`, but this is unwanted.
        bool left.is?(right)
      when {"is", _, MBool}
        # Returns whether *left*, converted to bool
        # **non-semantically**, is *right*.
        may_be left, if: left.to_bool.is?(right)
      when {"is", _, _}
        # Note that 'is' does not normalize; identity handling,
        # with all its sugars & salts, is done by *left*.
        may_be left, if: left.is?(right)
      when {"in", Str, Str}
        # Checks for substring. Returns *left*, or bool false.
        may_be left, if: right.value.includes?(left.value)
      when {"in", Num, MRange}
        # Checks for presence in range. Returns *left*, or
        # bool false.
        may_be left, if: right.includes?(left.value)
      when {"in", MCompoundType, Vec}
        # Returns a vector of values matching the specified
        # compound type, or an empty vector.
        vec right.select(&.is? left)
      when {"in", MBool, Vec}
        # Returns whether boolean *left* is in the vector.
        # Returns true or false.
        truthy = left.true?
        bool right.any? &.true?.==(truthy)
      when {"in", _, Vec}
        # Searches for an item matching *left* in the vector.
        # Returns the found item, or bool false.
        right.find &.is?(left) || bool false
      when {"in", Str, MMap}
        # Searches for a key named *left*, and returns the
        # corresponding value. Otherwise, returns bool false.
        may_be right[left.value], if: right.has_key?(left.value)
      when {"in", _, MMap}
        # Returns a subset map of *right* with only the values
        # matching *left* kept.
        MMap.new right.select { |_, v| v.is?(left) }
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
        vec left.items + right.items
      when {"~", Str, Str}
        str left.value + right.value
      when {"%", MMap, MMap}
        MMap.new(left.merge(right.map))
      when {"x", Vec, Num}
        vec left.items * right.value.to_big_i
      when {"x", Str, Num}
        str left.value * right.value.to_big_i
      else
        binary operator, *normalize(operator, left, right)
      end
    rescue DivisionByZeroError
      die("'#{operator}': division by zero given #{left}, #{right}")
    rescue OverflowError
      die("'#{operator}': numeric overflow")
    end

    # Normalizes a binary operation (i.e., converts it to its
    # normal form).
    #
    # Returns nil if found no matching conversion.
    def normalize?(operator : String, left : Model, right : Model)
      case operator
      when "to"
        return left.to_num, right.to_num
      when "x"
        case {left, right}
        when {_, Vec}, {_, Str}
          return right, left.to_num
        when {Str, _}, {Vec, _}
          return left, right.to_num
        else
          return left.to_vec, right.to_num
        end
      when "<", ">", "<=", ">="
        case {left, right}
        when {Str, Str}
          return left.to_num(parse: false), right.to_num(parse: false)
        else
          return left.to_num, right.to_num
        end
      when "+", "-", "*", "/"
        return left.to_num, right.to_num
      when "~"
        return left.to_str, right.to_str
      when "&"
        return left.to_vec, right.to_vec
      when "%"
        return left.to_map, right.to_map
      end
    rescue ModelCastException
    end

    # Normalizes a binary operation (i.e., converts it to its
    # normal form).
    #
    # Dies if found no matching conversion.
    def normalize(operator, left, right)
      normalize?(operator, left, right) ||
        die("'#{operator}': could not normalize: #{left.type}, #{right.type}")
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
      when MLambda
        # pass
      when MFunction
        if existing != defee
          defee = MGenericFunction.new(name)
            .add!(existing)
            .add!(defee)
        end
      end

      @context[symbol] = defee
    end

    # Reduces vector *operand* using a binary *operator*.
    #
    # Note:
    # - If *operand* is empty, returns it back.
    # - If *operand* has one item, returns that one item.
    def reduce(operator : String, operand : Vec)
      case operator
      when "and"
        # Returns the first false, orelse the last value, in
        # the vector.
        return operand.each { |x| return bool false if x.false? } || operand.last
      when "or"
        # 'or' returns the first non-false in the vector,
        # orelse false.
        return operand.each { |x| return x unless x.false? } || bool false
      end

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

    # Reduces range *operand* using a binary *operator*.
    def reduce(operator, operand : MFullRange)
      start = operand.begin.value
      end_ = operand.end.value

      case operator
      when "+"
        return num ((start + end_) * operand.length) / 2
      when "*"
        start = operand.begin.value
        end_ = operand.end.value

        # Uses GMP's factorial, which is MUCH faster than any
        # domestic implementation.
        if start < 0 || end_ < 0
          die("|*|: negative ends disallowed")
        elsif start == 1
          return num end_.value.factorial
        elsif start > end_
          return num (start - end_).value.factorial
        else
          return num (end_ - start).value.factorial
        end
      end

      reduce(operator, operand.to_vec)
    end

    # Fallback reduce (converts *operand* to vec).
    def reduce(operator, operand)
      reduce(operator, operand.to_vec)
    end

    # Resolves field access.
    #
    # If *head* has a field named *field*, returns the value
    # of that field.
    #
    # Otherwise, tries to construct a partial from a function
    # called *field*, if it exists.
    #
    # Returns nil if found no valid field resolution.
    def field?(head : Model, field : Str)
      head.field(field.value) || field?(head, @context[field.value]?)
    end

    # :ditto:
    def field?(head : Vec, field : MFunction)
      if field.leading?(MType[Vec])
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
      field?(head, field) || vec (head.map do |item|
        if item.is_a?(Vec)
          # Enable recursion.
          # ~> [[1, 2, 3], [4, 5], 6].a
          # == [[1.a, 2.a, 3.a], [4.a, 5.a], 6.a]
          field(item, field)
        else
          # If there is no such field, ignore:
          # ~> [1, 2, has-a].a
          # == [1, 2, val-of-a]
          field?(item, field) || item
        end
      end)
    end

    # Same as `field?`, but dies if found no working field
    # resolution.
    def field(head : Model, field : Model)
      field?(head, field) || die("#{head.type}: no such field or function: #{field}")
    end

    # Starts a primitive state inspector prompt.
    #
    # Returns false if the user wanted to terminate the
    # inspector altogether, or true if the user requested
    # the next instruction.
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
    def start(schedule = true)
      # The amount of ticks gone by. A tick is one iteration
      # of the interpreter loop. Ven runtime scheduler works
      # with this number to figure out when to run tasks.
      ticks = 0_u128

      # Whether it received an interrupt signal.
      interrupt = false

      if schedule
        Signal::INT.trap do
          interrupt = true
        end
      end

      while this = fetch?
        # Remember the chunk we are/(at the end, possibly were)
        # in and the current instruction pointer.
        ip, cp = frame.ip, frame.cp

        if schedule
          # Loosen up the loop from time to time.
          #
          # HELL THIS IS CRUDE!
          if ticks % SCHEDULER_TICK_PERIOD == 0
            Fiber.yield
          end

          ticks += 1
        end

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
            in Opcode::POP
              # Pops one value from the stack: (x --)
              pop
            in Opcode::POP2
              # Pops two values from the stack (x1 x2 --)
              pop 2
            in Opcode::SWAP
              # Swaps two last values on the stack: (x1 x2 -- x2 x1)
              stack.swap(-2, -1)
            in Opcode::TRY_POP
              # Same as POP, but does not raise on underflow.
              stack.pop?
            in Opcode::DUP
              # Makes a duplicate of the last value: (x1 -- x1 x1')
              put tap
            in Opcode::CLEAR
              # Clears the stack: (x1 x2 x3 ... --)
              stack.clear
            in Opcode::SYM
              # Puts the value of a symbol: (-- x)
              put lookup(symbol)
            in Opcode::NUM
              # Puts a number: (-- x)
              put num static(BigDecimal)
            in Opcode::STR
              # Puts a string: (-- x)
              put str static
            in Opcode::PCRE
              # Puts a regex: (-- x)
              begin
                put regex static
              rescue e : ArgumentError
                die("bad regex: #{e.message}")
              end
            in Opcode::VEC
              # Joins multiple values under a vector: (x1 x2 x3 -- [x1 x2 x3])
              put vec pop static(Int32)
            in Opcode::TRUE
              # Puts true: (-- true)
              put bool true
            in Opcode::FALSE
              # Puts false: (-- false)
              put bool false
            in Opcode::FALSE_IF_EMPTY
              # Puts false if stack is empty:
              #  - (-- false)
              #  - (... -- ...)
              put bool false if stack.empty?
            in Opcode::ANY
              # Puts 'any' onto the stack: (-- any)
              put MAny.new
            in Opcode::NEG
              # Negates a num: (x1 -- -x1)
              put -pop.to_num
            in Opcode::TON
              # Converts to num: (x1 -- x1' : num)
              put pop.to_num
            in Opcode::TOS
              # Converts to str: (x1 -- x1' : str)
              put pop.to_str
            in Opcode::TOB
              # Converts to bool. TOB (aka postfix '?') is the
              # only way you can get a *semantic boolean* (e.g.
              # outside of '?', 0 is true; but `0?` is false).
              # (x1 -- x1' : bool)
              semantic =
                case value = pop
                when Num
                  value.positive?
                when Str, Vec, MMap
                  !value.empty?
                else
                  value.true?
                end

              put bool semantic
            in Opcode::TOIB
              # Inverts the given boolean.
              #   - (x1.true? -- false)
              #   - (x1.false? -- true)
              put pop.to_bool(inverse: true)
            in Opcode::TOV
              # Converts to vec (unless vec):
              #   - (x1 -- [x1])
              #   - ([x1] -- [x1])
              put pop.to_vec
            in Opcode::LEN
              # Puts length of an entity: (x1 -- x2)
              put num pop.length
            in Opcode::TOR_BL
              # Makes a beginless range: (x1 -- x2)
              put MPartialRange.new(to: pop.to_num)
            in Opcode::TOR_EL
              # Makes an endless range: (x1 -- x2)
              put MPartialRange.new(from: pop.to_num)
            in Opcode::TOM
              # Converts to map (type map).
              put pop.to_map
            in Opcode::BINARY
              # Evaluates a binary operation: (x1 x2 -- x3)
              lhs, rhs = pop 2
              put binary(static, lhs, rhs)
            in Opcode::BINARY_ASSIGN
              # Almost the same as BINARY, but used specifically
              # in binary assignment.
              put binary(static, pop, tap)
            in Opcode::ENS
              # Dies if tap is false: (x1 -- x1)
              die("ensure: got false") if tap.false?
            in Opcode::J
              # Jumps at some instruction pointer.
              jump target
            in Opcode::JIT
              # Jumps at some instruction pointer if not popped
              # bool false: (x1 --)
              jump target unless pop.false?
            in Opcode::JIF
              # Jumps at some instruction pointer if popped bool
              # false: (x1 --)
              jump target if pop.false?
            in Opcode::JIT_ELSE_POP
              # Jumps at some instruction pointer if not tapped
              # bool false; pops otherwise:
              #   - (true -- true)
              #   - (false --)
              tap.false? ? pop : jump target
            in Opcode::JIF_ELSE_POP
              # Jumps at some instruction pointer if tapped bool
              # false; pops otherwise:
              #   - (true --)
              #   - (false -- false)
              tap.false? ? jump target : pop
            in Opcode::POP_ASSIGN
              # Pops and assigns it to a symbol: (x1 --)
              assign symbol, pop
            in Opcode::TAP_ASSIGN
              # Taps and assigns it to a symbol: (x1 -- x1)
              assign symbol, tap
            in Opcode::INC
              # Implements inplace-increment semantics: (-- x1)
              this = symbol
              operand = lookup(this)
              @context[this] = num operand.to_num.value + 1
              put operand
            in Opcode::DEC
              # Implements inplace-decrement semantics: (-- x1)
              this = symbol
              operand = lookup(this)
              @context[this] = num operand.to_num.value - 1
              put operand
            in Opcode::REST
              # Defines the `*` variable. Pops stack.size - static
              # values.
              @context["*"] = vec pop(stack.size - static Int32)
            in Opcode::FUN
              # Defines a function. Requires the values of the
              # given appendix (orelse the appropriate number of
              # `any`s) to be on the stack; it pops them.
              defun(myself = function, pop myself.given)
            in Opcode::CALL
              # If *x1* is a fun/box, invokes it. If an indexable,
              # calls __iter on it: (x1 a1 a2 a3 ... -- R), where
              # *aN* is an argument, and R is the returned value.
              args = pop static(Int32)

              case callee = pop
              when .indexable?
                next hook("__iter", [callee.as(Model)] + args)
              when MType, MAny
                put MCompoundType.new(callee, args)
              when MFunction
                if callee.is_a?(MPartial)
                  # Append the arguments of the call to the
                  # arguments of the partial: partial `1.foo`,
                  # if called like so: `1.foo(2, 3)` - will
                  # after this become `do(1, 2, 3)`.
                  callee, args = callee.function, callee.args + args
                end

                found = callee.variant?(args)

                # *found*, too, can be an `MPartial`. At least,
                # no one can protect us from that.
                if found.is_a?(MPartial)
                  found, args = found.function, found.args + args
                end

                case found
                when MBox
                  next invoke(found.target, found.to_s, args, Frame::Goal::Unknown)
                when MConcreteFunction
                  next invoke(found.target, found.to_s, args)
                when MBuiltinFunction
                  put found.callee.call(self, args)
                when MFrozenLambda
                  put found.call(args)
                when MLambda
                  # Invoke the lambda manually, as it's not
                  # worth it to make this a special-case of
                  # invoke():
                  @frames << Frame.new(Frame::Goal::Function, args, found.target)
                  # Make use of the lambda's contextuals.
                  underscores.concat(found.contextuals)
                  @context.push(isolated: true, initial: found.scope.clone)
                  next
                else
                  die("argument/parameter mismatch for #{callee.to_s}: #{args.join(", ")}")
                end
              else
                die("illegal callee: #{callee.type}")
              end
            in Opcode::RET
              # Returns from a function. Puts onto the parent stack
              # the return value defined by the function frame,
              # unless it wasn't specified. In that case, exports
              # the last value from the function frame's operand
              # stack.
              if !(queue = frame.queue).empty?
                revoke && put vec queue
              elsif returns = frame.returns
                revoke && put returns
              elsif !revoke(export: true)
                die("void expression")
              end
            in Opcode::POP_UPUT
              # Moves a value onto the underscores stack:
              #   oS: (x1 --) ==> _S: (-- x1)
              underscores << pop
            in Opcode::TAP_UPUT
              # Copies a value onto the underscores stack:
              #   oS: (x1 -- x1) ==> _S: (-- x1)
              underscores << tap
            in Opcode::UPOP
              # Moves a value from the underscores stack:
              put u_lookup || die("'_': no contextual")
            in Opcode::UREF
              # Moves a copy of a value from the underscores stack
              # to the stack:
              put u_lookup(pop: false) || die("'&_': no contextual")
            in Opcode::MAP_SETUP
              # Prepares for a series of `MAP_ITER`s on a vector.
              control << tap.length << 0 << stack.size - 2
            in Opcode::MAP_ITER
              # Executes each map iteration. Assumes:
              #   - that control[-2] is the current item index
              #     in an operand vector;
              #   - that control[-3] is the length of that
              #     operand vector;
              length, index, _ = control.last(3)

              if index >= length
                control.pop(3) && jump target
              else
                put tap.as(Vec)[index]
              end

              control[-2] += 1
            in Opcode::MAP_APPEND
              # A variation of "&" for maps. Assumes that control[-1]
              # is a stack pointer to a destination vector.
              stack[control.last].as(Vec) << pop
            in Opcode::REDUCE
              # Reduces a vector using a binary operator: ([...] -- x1)
              put reduce(static, pop)
            in Opcode::GOTO
              # Goes to the chunk it received as the argument.
              next invoke(static(Int32), goal: Frame::Goal::Unknown)
            in Opcode::ACCESS
              # Provides a conventional interface to .indexable?
              # Model's items. May collect (`[1, 2, 3][0, 1]`)
              # items or return a specific one (`[1, 2, 3][0]`).
              args = pop static(Int32)
              head = pop

              unless head.indexable?
                die("[]: head not indexable")
              end

              # Collect nth items in *head*.
              nths = args.map do |arg|
                head[arg]? || die("#{head.type}: item(s) not found: #{arg}")
              end

              # If there was one value collected, we put it
              # bare. If there were more, we wrap them in
              # a vec.
              nths.size == 1 ? put nths.first : put vec nths
            in Opcode::FIELD_IMMEDIATE
              # Pops an operand and, if possible, gets the value
              # of its field. Alternatively, builds a partial:
              # (x1 -- x2)
              put field(pop, str static)
            in Opcode::FIELD_DYNAMIC
              # Pops two values, first being the operand and
              # second the field, and, if possible, gets the
              # value of the field. Alternatively, builds a
              # partial: (x1 x2 -- x3)
              head, field = pop 2
              put field(head, field)
            in Opcode::NEXT_FUN
              # Performs an explicitly requested tail call.
              # Queue is preserved. Pops the callee and N
              # arguments. (x1 ...N --)
              args = pop static(Int32)
              callee = pop as: MFunction

              rewind(Frame::Goal::Function) do |it|
                unless variant = callee.variant?(args)
                  die("argument/parameter mismatch for #{callee.to_s}: #{args.join(", ")}")
                end
                unless variant.is_a?(MConcreteFunction)
                  die("unsupported: #{callee.to_s} resolved to non-concrete #{variant}")
                end

                invoke(variant.target, variant.to_s, args)

                # Move queue values from the revoked frame to
                # the new frame.
                frame.queue = it.queue
              end

              next
            in Opcode::SETUP_DIES
              # Sets the 'dies' target of this frame. The
              # 'dies' target is jumped to whenever a runtime
              # error occurs.
              frame.dies = target
            in Opcode::RESET_DIES
              # Resets the 'dies' target of this frame.
              frame.dies = nil
            in Opcode::FORCE_RET
              # Immediately returns with return value popped.
              # Vetoes `SETUP_RET`. (x1 --)
              value = pop
              rewind(Frame::Goal::Function) do |it|
                put value
              end
            in Opcode::FORCE_RET_QUEUE
              # Immediately returns with queue as the return value.
              rewind(Frame::Goal::Function) do |it|
                put vec it.queue
              end
            in Opcode::SETUP_RET
              # Finds the nearest surrounding function and sets
              # its return value to tap. Does not break the flow.
              # (x1 -- x1)
              frame(Frame::Goal::Function) do |it|
                it.returns = tap
              end
            in Opcode::BOX
              # Makes a box and puts in onto the stack: (...N) -- B,
              # where N is the number of arguments a box receives
              # and B is the resulting box.
              defee = function
              name = defee.symbol.name
              given = pop defee.given

              put MBox.new(
                name, given,
                defee.params,
                defee.arity,
                defee.target
              )
            in Opcode::BOX_INSTANCE
              # Instantiates a box and puts the instance onto the
              # stack: (B -- I), where B is the box parent to this
              # instance, and I is the instance.
              put MBoxInstance.new(pop(as: MFunction), @context.scopes.last.as_h)
            in Opcode::LAMBDA
              # Makes a lambda from the function it receives
              # as the argument. Assumes there is at least
              # one scope in the scope hierarchy.
              lambda = function

              put MLambda.new(
                context.gather,
                lambda.arity,
                lambda.slurpy,
                lambda.params,
                lambda.target,
              )
            in Opcode::TEST_TITLE
              # Pops and uses that to print ensure test title.
              puts "[#{chunk.file}]: #{pop(as: Str).value}".colorize.bold
            in Opcode::TEST_ASSERT
              # Checks if tap is false, and, if it is, emits
              # a failure.
              if tap.false?
                frame.failures << "#{chunk.file}:#{this.line}: got #{tap.to_s}"
              end
            in Opcode::TEST_SHOULD
              # Checks if there are any failures in this frame's
              # `failures` and, if there are, prints them under a
              # test case section (provided by static).
              if frame.failures.empty?
                puts " #{"✓".colorize.bold.green} #{static}"
              else
                puts " ❌ #{static}".colorize.bold.red
                frame.failures.each do |failure|
                  puts "\t◦ #{failure}"
                end
              end
            in Opcode::QUEUE
              # Appends the tapped value to the queue of the
              # frame of the closest surrounding function.
              frame(Frame::Goal::Function) do |it|
                it.queue << tap
              end
            in Opcode::MAP
              # Puts a map (short for mapping). Pops the specified
              # amount of key-values and makes a map out of them.
              items = pop(static Int32)
              pairs = [] of {String, Model}

              items.in_groups_of(2, reuse: true) do |group|
                key, val = group[0].not_nil!, group[1].not_nil!
                # Convert to str so we don't have to deal
                # with mutable keys.
                pairs << {key.to_str.value, val}
              end

              put MMap.new(pairs.to_h)
            end
          rescue error : ModelCastException
            die(error.message.not_nil!)
          end
        rescue error : RuntimeError
          @enquiry.broadcast("Error", error)

          dies = @frames.reverse_each do |it|
            break it.dies || next revoke
          end

          unless dies
            # Re-raise if climbed up all frames & didn't find
            # a 'dies' handler.
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

          if @enquiry.broadcast
            @enquiry.broadcast("Frames", @frames)
            @enquiry.broadcast("Instruction", {
              "Content" => this,
              "Nanos"   => (Time.monotonic - began.not_nil!).total_nanoseconds,
            })
          end

          # If there is anything left to inspect (there is
          # nothing in case of an error), and if inspector
          # functionality itself is enabled, then inspect.
          if !@frames.empty? && @inspect
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

    # Yields an instance of `Machine`, and then runs that instance.
    # You can use the block to configure the instance.
    def self.run(chunks, context = CxMachine.new, origin = 0)
      yield machine = new(chunks, context, origin)
      machine.start.return!
    end

    # Same as `run`, but configures the machine based on
    # the arguments.
    def self.run(chunks, context = CxMachine.new, origin = 0, enquiry = Enquiry.new)
      new(chunks, context, origin, enquiry).start.return!
    end
  end
end
