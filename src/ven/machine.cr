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

    # Origin chunk. It only makes sense to set it just before
    # evaluation, otherwise it is ignored.
    property origin = 0
    # Whether to enable inspector functionality (see `inspector`)
    property inspect = false
    # Whether to take the appropriate measurements, and write
    # them to the timetable.
    property measure = false
    # The target `Timetable` Hash.
    property timetable = Timetable.new
    # Returns the current frame stack of this machine.
    property frames = Array(Frame).new

    # Returns the chunks this machine is aware of.
    getter chunks : Chunks
    # Returns the context of this machine.
    getter context : CxMachine

    # Makes a `Machine` which is aware of *chunks*. Upon `start`,
    # the machine will execute the `origin`-th chunk.
    def initialize(@chunks, @context = CxMachine.new)
      @frames = [Frame.new(cp: @origin)]
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

    # Builds an `IStatistic` given *amount*, *duration*
    # and *instruction*.
    private macro stat(amount, duration, instruction)
      { amount: {{amount}},
        duration: {{duration}},
        instruction: {{instruction}} }
    end

    # Updates the timetable entry for the given *instruction*.
    #
    # *duration* is the time *instruction* took to execute.
    #
    # *cp* is the index of the chunk where the *instruction*
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

    # Yields with the closest frame labeled *label*.
    private macro frame(label, &block)
      @frames.reverse_each do |%frame|
        if %frame.label == {{label}}
          {{*block.args}} = %frame
          {{yield}}
          break
        end
      end
    end

    # Same as `frame(label, &block)`, but destructive to all
    # frames it visited before, and including, the frame with
    # the matching *label*.
    private macro rewind(to label, &block)
      @frames.reverse_each do |%frame|
        revoke
        if %frame.label == {{label}}
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

    # Returns the instruction at the active instruction pointer.
    # Raises if there is no such instruction.
    private macro fetch
      chunk[frame.ip]
    end

    # Returns the instruction at the active instruction pointer,
    # or nil if the active instruction pointer overflows the
    # amount of available instructions.
    private macro fetch?
      if (%ip = frame.ip) < chunk.size
        chunk[%ip]
      end
    end

    # Jumps to the next instruction.
    private macro jump
      frame.ip += 1
    end

    # **Immediately** jumps to the instruction at *ip*.
    private macro jump(ip)
      next frame.ip = ({{ip}}.not_nil!)
    end

    # Assumes *source* instruction's argument is a `VJump`,
    # and returns its target (see `VJump#target`). Raises
    # otherwise.
    private macro target(source = this)
      chunk.resolve({{source}}).as(VJump).target
    end

    # Assumes *source* instruction's argument is a `VStatic`
    # with value of type *cast*, and returns the value as
    # such. Raises otherwise.
    private macro static(cast = String, source = this)
      chunk.resolve({{source}}).as(VStatic).value.as({{cast}})
    end

    # Assumes *source* instruction's argument is a `VSymbol`,
    # and returns it as such. Raises otherwise.
    private macro symbol(source = this)
      chunk.resolve({{source}}).as(VSymbol)
    end

    # Assumes *source* instruction's argument is a `VFunction`,
    # and returns it as such. Raises otherwise.
    private macro function(source = this)
      chunk.resolve({{source}}).as(VFunction)
    end

    # If *condition* is true, returns *value*. Otherwise,
    # returns *fallback* (`MBool` false by default).
    private macro may_be(value, if condition, fallback = bool false)
      {{condition}} ? {{value}} : {{fallback}}
    end

    # Puts *value* onto the stack.
    private macro put(value)
      frame.stack << ({{value}})
    end

    # If *condition* is true, puts *value* onto the stack.
    # Otherwise, puts `MBool` false.
    private macro put(value, if condition)
      frame.stack << may_be ({{value}}), if: ({{condition}})
    end

    # Puts *values* onto the stack.
    private macro put(*values)
      {% for value in values %}
        put {{value}}
      {% end %}
    end

    # If *condition* is true, puts *values* onto the stack.
    # Otherwise, puts `MBool` false.
    private macro put(*values, if condition)
      may_be put *values, if: {{condition}}
    end

    # Returns the topmost value on the stack. *cast* can be
    # passed to ensure the type of the value.
    #
    # Raises on underflow.
    private macro tap(cast = Model)
      frame.stack[-1].as({{cast}})
    end

    # Pops *amount* values from the stack. Keeps their order.
    # *cast* can be passed to ensure the type of each value.
    #
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

    # Performs abstract invokation: pushes a scope, and appends
    # a frame to `@frames`. Makes a trace given the *desc*ription
    # of the frame. Initiates the frame's stack with *initial*
    # values. Sets the frame's label to *label*.
    #
    # See `Context#push` to learn about *borrow* and *isolated*.
    private macro invoke(origin, desc = nil, initial = nil, label = nil, borrow = false, isolated = false)
      # Push the scope:
      @context.push(
        borrow: {{borrow}},
        isolated: {{isolated}},
      )
      # ... and the frame:
      @frames << Frame.new(
        cp: {{origin}},
        label: {{label}} || Frame::Label::Function,
        stack: {{initial}} || Models.new,
        {% if desc %}
          # Make a trace if got *desc*.
          trace: Trace.new(chunk.file, fetch.line, {{desc}}),
        {% end %}
      )
    end

    # Tears down an invokation.
    #
    # If *export* is true, requests a return value from
    # the invokation. Returns the value, or nil if there
    # isn't any.
    #
    # If *export* is false, always returns true.
    private macro revoke(export = false)
      @context.pop

      %frame = @frames.pop

      {% if export %}
        (%return = %frame.stack.last?) && put %return
      {% else %}
        true
      {% end %}
    end

    # Invokes a hook function called *name*.
    #
    # A hook function is a Ven function directly invoked by
    # the interpreter.
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

    # Looks up and returns the value of the given `VSymbol`,
    # *symbol*, or dies if it was not found.
    private macro lookup(symbol)
      @context[%it = {{symbol}}]? || die("symbol not found: #{%it.name}")
    end

    # Assigns `VSymbol` *target* to *value*. If *value* is a
    # lambda, sets `MLambda#myself` to *target*. Returns *value*.
    private macro assign(target, value)
      %target = {{target}}.as(VSymbol)
      %value  = {{value}}

      # Make lambdas recursive. As lambdas gather immediately,
      # they can't gather themselves.
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
        left < right
      when {">", Num, Num}
        left > right
      when {"<=", Num, Num}
        left <= right
      when {">=", Num, Num}
        left >= right
      when {"+", Num, Num}
        left + right
      when {"-", Num, Num}
        left - right
      when {"*", Num, Num}
        left * right
      when {"/", Num, Num}
        left / right
      when {"&", Vec, Vec}
        left + right
      when {"~", Str, Str}
        left + right
      when {"%", MMap, MMap}
        MMap.new(left.merge(right.map))
      when {"x", Vec, Num}
        left * right
      when {"x", Str, Num}
        left * right
      else
        binary operator, *normalize(operator, left, right)
      end
    rescue DivisionByZeroError
      die("'#{operator}': division by zero given #{left}, #{right}")
    rescue OverflowError
      die("'#{operator}': numeric overflow")
    end

    # Normalizes (converts down to the normal form) a binary
    # operation. Returns nil if failed to convert.
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

    # Normalizes (converts down to the normal form) a binary
    # operation. Dies if failed to convert.
    def normalize(operator, left, right)
      normalize?(operator, left, right) ||
        die("'#{operator}': could not normalize: #{left.type?}, #{right.type?}")
    end

    # Defines an `MFunction` off the *informer* and *given*s.
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
        # pass to overwrite
      when MFunction
        unless existing == defee
          defee = MGenericFunction.new(name)
            .add!(existing)
            .add!(defee)
        end
      end

      @context[symbol] = defee
    end

    # Reduces vector *operand* using a binary *operator*.
    #
    # - If *operand* is empty, returns it.
    # - If *operand* has one item, returns that one item.
    def reduce(operator : String, operand : Vec)
      return operand if operand.length == 0

      case operator
      when "and"
        # Returns the first false, orelse the last value, in
        # the operand vector.
        return operand.each { |x| return bool false if x.false? } || operand.last
      when "or"
        # Returns the first non-false, orelse false, in the
        # operand vector.
        return operand.each { |x| return x unless x.false? } || bool false
      end

      return operand.first if operand.length == 1

      memo = binary(operator, operand[0], operand[1])
      operand[2..].reduce(memo) do |total, current|
        binary(operator, total, current)
      end
    end

    # Reduces *operand*, a range, using a binary *operator*.
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

    # Fallback reduce (converts *operand* to vec & reduces).
    def reduce(operator, operand)
      reduce(operator, operand.to_vec)
    end

    # Resolves field access.
    #
    # If *head* has a field named *field*, returns the value
    # of that field.
    #
    # Otherwise, tries to construct a partial from a function
    # called *field*.
    #
    # If failed, returns nil.
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
    # Otherwise, spreads field access on the items of *head*.
    # E.g., `[1, 2, 3].a is [1.a, 2.a, 3.a]`. Identity if item
    # has no such field.
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

    # Same as `field?`, but dies if failed.
    def field(head : Model, field : Model)
      field?(head, field) || die("#{head.type?}: no such field or function: #{field}")
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
            "._ : display superlocals",
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
    # instructions from the active chunk and execute them,
    # until there aren't any.
    #
    # If *schedule* is true, the scheduler is enabled.
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
        # Remember the chunk pointer and the instruction pointer
        # we were executing in the beginning.
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
              # Pops a value from the stack: (x --).
              pop
            in Opcode::SWAP
              # Swaps two last values on the stack: (x1 x2 -- x2 x1)
              stack.swap(-2, -1)
            in Opcode::TRY_POP
              # Same as POP, but does not raise on underflow.
              stack.pop?
            in Opcode::DUP
              # "Duplicates" the last value: (x1 -- x1 x1')
              put tap
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
              # Defines the `*`. Pops `stack.size - static` values,
              # and makes a vector of them. Subsequently, this vector
              # becomes the value of `*`.
              @context["*"] = vec pop(stack.size - static Int32)
            in Opcode::FUN
              # Defines a function. Pops the values of `given`,
              # specified by the `VFunction` instruction argument.
              defun(myself = function, pop myself.given)
            in Opcode::CALL
              # If *x1* is an `MFunction`, invokes it. If an indexable,
              # calls `__iter`: (x1 a1 a2 a3 ... -- R), where *aN* is
              # an argument, and R is the returned value.
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
                  # after this become `foo(1, 2, 3)`.
                  callee, args = callee.function, callee.args + args
                end

                found = callee.variant?(args)

                # Expand partial/generic until met something
                # else (including failure).
                #
                # This should prevent calls like the one below
                # from letting improper types in:
                #   `[1 "2" 3].partial-that-takes-num()`
                #
                # ... and add (theoretically) support for nested
                # generics (currently, there is no legal way
                # to make nested generics, and there is really
                # no need to).
                while found.is_a?(MPartial) || found.is_a?(MGenericFunction)
                  found = found.variant?(args)
                  if found.is_a?(MPartial)
                    found, args = found.function, found.args + args
                  end
                  if found.is_a?(MGenericFunction)
                    found = found.variant?(args)
                  end
                end

                case found
                when MBox
                  next invoke(found.target, found.to_s, args, label: Frame::Label::Unknown)
                when MConcreteFunction
                  next invoke(found.target, found.to_s, args)
                when MBuiltinFunction
                  put found.callee.call(self, args)
                when MFrozenLambda
                  put found.call(args)
                when MLambda
                  @frames << Frame.new(Frame::Label::Function, args, found.target)
                  # Make an isolated context, and clone the original
                  # scope to make sure the user doesn't change it in
                  # the lambda body.
                  next @context.push(isolated: true, initial: found.scope.clone)
                else
                  die("argument/parameter mismatch for " \
                      "#{callee.to_s}: #{args.join(", ")}")
                end
              else
                die("illegal callee: #{callee.type?}")
              end
            in Opcode::RET
              # Returns from the **active** frame. If the
              # return value is set for the active frame,
              # exports it onto the higher stack.
              if !(queue = frame.queue).empty?
                revoke && put vec queue
              elsif returns = frame.returns
                revoke && put returns
              elsif !revoke(export: true)
                die("void expression")
              end
            in Opcode::POP_SFILL
              # Fills the superlocals with the popped value.
              @context.sfill(pop)
            in Opcode::IF_SFILL
              # Fills the superlocals with the tapped value
              # unless it is a boolean.
              @context.sfill(tap) unless tap.is_a?(MBool)
            in Opcode::STAKE
              # Takes the active superlocal, and puts it onto
              # the operand stack.
              put @context.stake? || die("'_': could not borrow")
            in Opcode::STAP
              # Same as `STAKE`, but taps.
              put @context.stap? || die("'&_': could not borrow")
            in Opcode::MAP_SETUP
              # Prepares for a series of map iterations.
              control << tap.length << 0 << stack.size - 2
            in Opcode::MAP_ITER
              # Executes a map iteration. Assumes that control[-2]
              # is the index of the current item in the operand
              # vector, and that control[-3] is the length of
              # the operand vector.
              length, index, _ = control.last(3)
              if index >= length
                control.pop(3) && jump target
              else
                put tap.as(Vec)[index]
              end
              control[-2] += 1
            in Opcode::MAP_APPEND
              # A variation of binary "&", used exclusively
              # during map spreads. Assumes that control[-1]
              # is a stack pointer to the destination vector.
              stack[control.last].as(Vec) << pop
            in Opcode::MAP_OPERATE
              # Same as `GOTO`, but fills the superlocals
              # with the popped value.
              item = pop
              # Switch to the target chunk.
              invoke(static(Int32), label: Frame::Label::Unknown)
              # Fill the superlocals stack with the current
              # item, and go execute.
              next @context.sfill(item)
            in Opcode::REDUCE
              # Pops a vector, and reduces it using a binary
              # operator. The operator is provided by a `VStatic`
              # instruction argument.
              put reduce(static, pop)
            in Opcode::GOTO
              # Goes to the given chunk.
              next invoke(static(Int32),
                label: Frame::Label::Unknown,
                # `GOTO` doesn't prevent superlocals
                # from borrowing.
                borrow: true)
            in Opcode::ACCESS
              # Provides a convenient interface to `.indexable?`
              # Models' items. May collect (`[1, 2, 3][0, 1]`)
              # multiple, or return one (`[1, 2, 3][0]`).
              args = pop static(Int32)
              head = pop

              unless head.indexable?
                die("[]: #{head.type?} is not indexable")
              end

              nths = args.map do |arg|
                head[arg]? || die("#{head.type?}: item(s) not found: #{arg}")
              end

              # If *nths* consists of one value, put it bare.
              # Otherwise, wrap *nths* in a vec.
              nths.size == 1 ? put nths.first : put vec nths
            in Opcode::FIELD_IMMEDIATE
              # Pops a value, and, if possible, puts the value
              # of its field onto the stack. The name the field
              # is provided by the `VStatic` instruction argument.
              # Alternatively, builds a partial.
              put field(pop, str static)
            in Opcode::FIELD_DYNAMIC
              # Pops two values, the operand and the field,
              # and, if possible, gets the value of the field.
              # Alternatively, builds a partial.
              head, field = pop 2
              put field(head, field)
            in Opcode::NEXT_FUN
              # Performs an explicit tail call. Preserves the
              # queue. Pops the callee and the appropriate
              # amount of arguments. **Breaks the flow.**
              args = pop static(Int32)
              callee = pop as: MFunction

              rewind(Frame::Label::Function) do |it|
                unless variant = callee.variant?(args)
                  die("argument/parameter mismatch for " \
                      "#{callee.to_s}: #{args.join(", ")}")
                end

                unless variant.is_a?(MConcreteFunction)
                  die("unsupported: #{callee.to_s} resolved " \
                      "to non-concrete #{variant}")
                end

                invoke(variant.target, variant.to_s, args)

                # Keep the queue of the rewound frame.
                frame.queue = it.queue
              end

              next
            in Opcode::SETUP_DIES
              # Sets this frame's *dies* target to the `VJump`
              # instruction argument. The *dies* target is
              # jumped to whenever a runtime error occurs.
              frame.dies = target
            in Opcode::RESET_DIES
              # Resets the *dies* target of this frame.
              frame.dies = nil
            in Opcode::FORCE_RET
              # Pops a return value, and immediately returns.
              # Vetoes `SETUP_RET`. **Breaks the flow.**
              value = pop
              rewind(Frame::Label::Function) do |it|
                put value
              end
            in Opcode::FORCE_RET_QUEUE
              # Immediately returns, with queue as the return
              # value. **Breaks the flow.**
              rewind(Frame::Label::Function) do |it|
                put vec it.queue
              end
            in Opcode::SETUP_RET
              # Sets the return value of the surrounding function
              # frame to tap. **Does not break the flow.**
              frame(Frame::Label::Function) do |it|
                it.returns = tap
              end
            in Opcode::BOX
              # Makes an `MBox` from the `VFunction` instruction
              # argument: pops the appropriate amount of givens,
              # and puts the `MBox` onto the stack.
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
              # Pops an `MFunction`, which will act as the parent
              # for this box instance, instantiates, and puts the
              # box instance onto the stack.
              put MBoxInstance.new(pop(as: MFunction), @context.scopes.last.as_h)
            in Opcode::LAMBDA
              # Makes a lambda from the `VFunction` instruction
              # argument.
              lambda = function

              put MLambda.new(
                context.gather,
                lambda.arity,
                lambda.slurpy,
                lambda.params,
                lambda.target,
              )
            in Opcode::TEST_TITLE
              # Displays the popped value as ensure test title.
              puts "[#{chunk.file}]: #{pop(as: Str).value}".colorize.bold
            in Opcode::TEST_ASSERT
              # Checks if the tapped value is false, and, if it
              # is, appends a failure to this frame's failures.
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
              # surrounding function frame.
              frame(Frame::Label::Function) do |it|
                it.queue << tap
              end
            in Opcode::MAP
              # Puts a map (short for mapping). Pops the specified
              # amount of key-values and makes an `MMap` from them.
              items = pop(static Int32)
              pairs = [] of {String, Model}

              items.in_groups_of(2, reuse: true) do |(key, val)|
                # Convert to str so we don't have mutable keys.
                pairs << {key.not_nil!.to_str.value, val.not_nil!}
              end

              put MMap.new(pairs.to_h)
            in Opcode::MATCH
              # Pops a value, which is assumed to be the return
              # value of a pattern lambda, and the lambda's
              # matchee. If the value is false, dies of pattern
              # match error (**there is no generic recovery
              # from a pattern match error in a variant** in
              # Ven; `given` is well enough for variant choosing!)
              # If the value is an MMap, makes a new scope out
              # of it and pushes the scope onto the scope stack.
              # Noop otherwise.
              paramno = static(Int32) + 1
              matchee, value = pop(2)

              case value
              when .false?
                die("pattern for parameter no. #{paramno} could not " \
                    "match against the given argument: #{matchee}")
              when MMap
                context.current.as_h.merge!(value.map)
              end
            end
          rescue error : ModelCastException
            die(error.message.not_nil!)
          end
        rescue error : RuntimeError
          dies = @frames.reverse_each do |it|
            break it.dies || next revoke
          end

          unless dies
            # Re-raise if climbed up all frames but didn't
            # find a 'dies' handler.
            raise error
          end

          jump(dies)
        ensure
          if @measure && began
            record!(this, Time.monotonic - began, cp, ip)
          end

          # If there is anything left to inspect (there is
          # nothing in case of an error), and if inspector
          # itself is enabled, then inspect.
          if !@frames.empty? && @inspect
            @inspect = inspector
          end
        end

        jump
      end

      self
    end

    # Returns the last value on the operand stack, if any.
    def return!
      stack.last?
    end
  end
end
