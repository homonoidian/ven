require "fancyline"
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

    getter context : Context::Machine

    @timetable : Timetable

    # Makes a `Machine` that will run *chunks*, an array of
    # stitched chunks.
    #
    # *context* is the context that the Machine will run in.
    # *origin* is the first chunk that will be evaluated (the
    # main chunk).
    def initialize(@chunks : Chunks, @context = Context::Machine.new,
                   origin = 0, @enquiry = Enquiry.new)
      @inspect = @enquiry.inspect.as Bool
      @measure = @enquiry.measure.as Bool
      @fast_interrupt = @enquiry.fast_interrupt.as Bool

      # Remember: per each frame there should always be a scope;
      # if you push a frame, that is, you have to push a scope
      # too. This has to be done so that the frames and the
      # context scopes are in sync.
      @frames = [Frame.new(cp: origin)]
      @timetable = @enquiry.timetable = Timetable.new
    end

    # Dies of runtime error with *message*, which should explain
    # why the error happened.
    def die(message : String)
      traces = @context.traces.dup

      file = chunk.file
      line = fetch.line

      unless traces.last?.try(&.line) == line
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
      @frames[-1]
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
      @context.push(chunk.file, fetch.line, {{name}})
      @frames << Frame.new({{goal}}, {{values}}, {{cp}})
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

      # Disable scope isolation (if it was enabled).
      @context.isolate = false

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
        die("hook '#{%name}' has no proper variant for #{%args.join(", ")}")
      end

      invoke(%callee.to_s, %variant.target, %args, Frame::Goal::Function)
    end

    # Looks up for an underscores value in the frames above
    # the current; depending on *pop*, will either return it,
    # or pop it in the appropriate frame and return it.
    #
    # Returns nil if no underscores value was found.
    private macro u_lookup(pop = true)
      @frames.reverse_each do |above|
        if it = {{pop}} ? above.underscores.pop? : above.underscores.last?
          break it
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
        # `str is regex` is a special case for `is`, for it
        # does not return the value of left, but instead the
        # whole match result.
        may_be str($0), if: right.regex === left.value
      when {"is", MBool, _}
        # `bool is any`  is also a special case, as, because
        # `is` returns *left* value, `false is false` will
        # return false (i.e., the left false); this is, of
        # course, wrong.
        bool left.is?(right)
      when {"is", _, _}
        # Note that 'is' is not normalized; identity handling
        # & all its oddities, sugars etc. is all done by the
        # *left* Model.
        may_be left, if: left.is?(right)
      when {"in", Str, Str}
        may_be left, if: right.value.includes?(left.value)
      when {"in", Num, MRange}
        may_be left, if: right.includes?(left.value)
      when {"in", _, Vec}
        # 'in' with vector is '|left is _| [...]' on steroids.
        may_be left, if: right.any? { |item| left.is?(item) }
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
      end_  = operand.end.value

      case operator
      when "+"
        return num ((start + end_) * operand.length) / 2
      when "*"
        start = operand.begin.value
        end_  = operand.end.value

        # Uses GMP's factorial. If got |*| -A to -B, outputs
        # -(|*| A to B); I don't know whether it's the expected
        # behavior. If |*| (A > 1) to (B > 1), outputs (B - A)!;
        # about this I also do not know.
        if neg = start < 0 && end_ < 0
          start = -start
          end_  = -end_
        elsif start < 0 || end_ < 0
          return num 0
        end

        sign = neg ? -1 : 1

        if start == 1
          return num sign * end_.value.factorial
        elsif start > end_
          return num sign * (start - end_).value.factorial
        else
          return num sign * (end_ - start).value.factorial
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
    # Provides a Ven field named 'callable?' to any *head*;
    # this field calls `Model.callable?`.
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
    def start
      interrupt = false

      unless @fast_interrupt
        Signal::INT.trap do
          interrupt = true
        end
      end

      while this = fetch?
        # Remember the chunk we are/(at the end, possibly were)
        # in and the current instruction pointer.
        ip, cp = frame.ip, frame.cp

        # De-busy the loop (a temporary solution).
        #
        # XXX: have some sort of scheduling logic do this? I.e.,
        # every 10 instructions `Fiber.yield` to see if an
        # interrupt was requested.
        Fiber.yield unless @fast_interrupt

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
              put -pop.to_num
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
            # Make a beginless range: (x1 -- x2)
            in Opcode::TOR_BL
              put MPartialRange.new(to: pop.to_num)
            # Make an endless range: (x1 -- x2)
            in Opcode::TOR_EL
              put MPartialRange.new(from: pop.to_num)
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
              assign symbol, pop
            # Taps and assigns it to a symbol: (x1 -- x1)
            in Opcode::TAP_ASSIGN
              assign symbol, tap
            # Implements inplace-increment semantics: (-- x1)
            in Opcode::INC
              this = symbol
              operand = lookup(this)
              @context[this] = num operand.to_num.value + 1
              put operand
            # Implements inplace-decrement semantics: (-- x1)
            in Opcode::DEC
              this = symbol
              operand = lookup(this)
              @context[this] = num operand.to_num.value - 1
              put operand
            # Defines the `*` variable. Pops stack.size - static
            # values.
            in Opcode::REST
              @context["*"] = vec pop(stack.size - static Int32)
            # Defines a function. Requires the values of the
            # given appendix (orelse the appropriate number of
            # `any`s) to be on the stack; it pops them.
            in Opcode::FUN
              defun(myself = function, pop myself.given)
            # If *x1* is a fun/box, invokes it. If an indexable,
            # indexes it: (x1 a1 a2 a3 ... -- R), where *aN* is
            # an argument, and R is the returned value.
            in Opcode::CALL
              args = pop static(Int32)

              case callee = pop
              when .indexable?
                if args.size != 0
                  values = args.map do |arg|
                    callee[arg]? || die("#{callee}: item(s) not found: #{arg}")
                  end

                  values.size == 1 ? put values.first : put vec values
                else
                  # Argumentless indexable call is a call spread:
                  #   `[1, 2, 3].say() # ==> 1\n2\n3\n`
                  next hook("__iter", [callee.as(Model)])
                end
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
                when MLambda
                  # Invoke the lambda manually, as it's not
                  # worth it to make this a special-case of
                  # invoke():
                  @frames << Frame.new(Frame::Goal::Function, args, found.target)
                  # Lambdas are isolated from the other scopes,
                  # although globals can still be accessed
                  # (their nest is known, and lookup prefers
                  # nest over isolation).
                  @context.isolate = true
                  # Worked without the 'dup', but it's required
                  # by semantics (is it?)
                  @context.scopes << found.scope.dup
                  @context.traces << Trace.new(chunk.file, fetch.line, "lambda")
                  next
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
              if !(queue = frame.queue).empty?
                revoke && put vec queue
              elsif returns = frame.returns
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
              put u_lookup || die("'_': no contextual")
            # Moves a copy of a value from the underscores stack
            # to the stack:
            in Opcode::UREF
              put u_lookup(pop: false) || die("'&_': no contextual")
            # Prepares for a series of `MAP_ITER`s on a vector.
            in Opcode::MAP_SETUP
              control << tap.length << 0 << stack.size - 2
            # Executes each map iteration. Assumes:
            #   - that control[-2] is the current item index
            #     in an operand vector;
            #   - that control[-3] is the length of that
            #     operand vector;
            in Opcode::MAP_ITER
              length, index, _ = control.last(3)

              if index >= length
                control.pop(3) && jump target
              else
                put tap.as(Vec)[index]
              end

              control[-2] += 1
            # A variation of "&" for maps. Assumes that control[-1]
            # is a stack pointer to a destination vector.
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
            #
            # Queue is always preserved.
            in Opcode::NEXT_FUN
              args   = pop static(Int32)
              callee = pop(as: MFunction)

              # Pop frames until we meet the nearest surrounding
              # function. We know there is one because we trust
              # the Compiler.
              @frames.reverse_each do |it|
                next revoke unless it.goal.function?

                variant = callee.variant?(args)

                unless variant.is_a?(MConcreteFunction)
                  die("improper 'next fun': #{callee}: #{args.join(", ")}")
                end

                # Revoke that surrounding function & invoke
                # the one requested by 'next'.
                revoke && invoke(variant.to_s, variant.target, args, Frame::Goal::Function)

                # But keep queue values from the revoked
                # function.
                frame.queue = it.queue

                break
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
                revoke; break put value if it.goal.function?
              end
            # Force-returns the queue of the nearest surrounding
            # function. Revokes all frames up to & including
            # the frame of that nearest surrounding function.
            in Opcode::FORCE_RET_QUEUE
              @frames.reverse_each do |it|
                revoke; break put vec it.queue if it.goal.function?
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
              put MBoxInstance.new(pop(as: MFunction), @context.scopes[-1].dup)
            # Makes a lambda from the function it receives
            # as the argument. Assumes there is at least
            # one scope in the scope hierarchy.
            in Opcode::LAMBDA
              lambda = function

              put MLambda.new(
                @context.scopes[-1].dup,
                lambda.arity,
                lambda.slurpy,
                lambda.params,
                lambda.target,
              )
            # Pops and uses that to print ensure test title.
            in Opcode::TEST_TITLE
              puts "[#{chunk.file}]: #{pop(as: Str).value}".colorize.bold
            # Checks if tap is false, and, if it is, emits
            # a failure.
            in Opcode::TEST_ASSERT
              if tap.false?
                frame.failures << "#{chunk.file}:#{this.line}: got #{tap}"
              end
            # Checks if there are any failures in this frame's
            # `failures` and, if there are, prints them under a
            # test case section (provided by static).
            in Opcode::TEST_SHOULD
              if frame.failures.empty?
                puts " #{"✓".colorize.bold.green} #{static}"
              else
                puts " ❌ #{static}".colorize.bold.red
                frame.failures.each do |failure|
                  puts "\t◦ #{failure}"
                end
              end
            # Appends the tapped value to the queue of the
            # frame of the closest surrounding function.
            in Opcode::QUEUE
              @frames.reverse_each do |it|
                break it.queue << tap if it.goal.function?
              end
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

    # Makes a `Machine`, runs *chunks* and disposes the `Machine`.
    #
    # *context* is the context that the Machine will run in.
    # *origin* is the first chunk that will be evaluated (the
    # main chunk).
    #
    # Before running, yields the `Machine` to the block.
    #
    # Returns the result that was produced by the Machine, or
    # nil if nothing was produced.
    def self.run(chunks, context = Context::Machine.new, origin = 0)
      machine = new(chunks, context, origin)
      yield machine
      machine.start.return!
    end

    # Makes a Machine, runs *chunks* and disposes the Machine.
    #
    # *context* is the context that the Machine will run in.
    # *origin* is the first chunk that will be evaluated (the
    # main chunk).
    #
    # Returns the result that was produced by the Machine, or
    # nil if nothing was produced.
    def self.run(chunks, context = Context::Machine.new, origin = 0,
                 legate = Enquiry.new)
      new(chunks, context, origin, legate).start.return!
    end
  end
end
