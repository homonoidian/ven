require "./suite/*"

module Ven
  # Provides the facilities to compile Ven quotes into a linear
  # sequence of Ven bytecode instructions.
  class Compiler < Suite::Visitor
    include Suite

    def initialize(@context : Context::Compiler, @file = "<unknown>")
      @cursor = 0
      @chunks = [Chunk.new(@file, "<unit>")]
    end

    # Raises a traceback-ed compile-time error.
    def die(message : String)
      traces = @context.traces.dup

      unless traces.last?.try(&.name) == "<unit>"
        traces << Trace.new(@last.tag, "<unit>")
      end

      raise CompileError.new(traces, message)
    end

    # Returns the chunk under the cursor.
    private macro lead
      @chunks[@cursor]
    end

    # Requests a new, unique label.
    private macro label?
      Label.new
    end

    # Declares a label in the lead chunk.
    private macro label(name)
      lead.label({{name}})
    end

    # Emits an instruction into the lead chunk.
    #
    # Ensures *opcode* is not nil.
    private macro emit(opcode, argument = nil)
      lead.add({{opcode}}.not_nil!, {{argument}}, @last.tag.line)
    end

    # Makes a new chunk, *name*, and evaluates the block
    # within it.
    #
    # Returns the chunk cursor for the new chunk.
    private macro chunk(name, &)
      @chunks << Chunk.new(@file, {{name}})

      # Make our chunk the lead chunk for the time the block
      # executes. This allows `emit` to target it.
      old, @cursor = @cursor, @chunks.size - 1

      begin
        {{yield}}

        @cursor
      ensure
        @cursor = old
      end
    end

    # Looks up a symbol or dies.
    private macro lookup(symbol)
      @context.lookup(%symbol = {{symbol}}) || die("symbol not found: #{%symbol}")
    end

    # A shorthand for `VSymbol.new(...)`.
    private macro symbol(name, nesting = nil)
      {% if nesting %}
        VSymbol.new({{name}}, {{nesting}})
      {% else %}
        VSymbol.new(%name = {{name}}, lookup %name)
      {% end %}
    end

    # Assigns a *symbol*. Returns the resulting `DSymbol`.
    private macro assign(symbol, global)
      %symbol = {{symbol}}
      %global = {{global}}
      %nesting = @context.assign({{symbol}}, {{global}})

      symbol(%symbol, %nesting)
    end

    # Returns the result of this compiler's work: an array of
    # unoptimized, snippeted chunks.
    def result
      @chunks
    end

    def visit!(q : QSymbol)
      emit Opcode::SYM, symbol(q.value)
    end

    def visit!(q : QNumber)
      emit Opcode::NUM, q.value
    end

    def visit!(q : QString)
      emit Opcode::STR, q.value
    end

    def visit!(q : QVector)
      emit Opcode::VEC, visit(q.items)
    end

    def visit!(q : QUPop)
      emit Opcode::UPOP
    end

    def visit!(q : QURef)
      emit Opcode::UREF
    end

    def visit!(q : QUnary)
      visit q.operand

      opcode =
        case q.operator
        when "+" then Opcode::TON
        when "-" then Opcode::NEG
        when "~" then Opcode::TOS
        when "#" then Opcode::LEN
        when "&" then Opcode::TOV
        when "not" then Opcode::TOIB
        end

      emit opcode
    end

    def visit!(q : QBinary)
      visit([q.left, q.right])

      emit Opcode::BINARY, q.operator
    end

    def visit!(q : QAssign)
      visit(q.value)

      emit Opcode::TAP_ASSIGN, assign(q.target, q.global)
    end

    def visit!(q : QCall)
      visit(q.callee)

      emit Opcode::CALL, visit(q.args)
    end

    def visit!(q : QIntoBool)
      visit(q.value)

      emit Opcode::TOB
    end

    def visit!(q : QReturnIncrement)
      symbol = symbol(q.target)

      emit Opcode::SYM, symbol
      emit Opcode::DUP
      emit Opcode::TON
      emit Opcode::INC
      emit Opcode::POP_ASSIGN, symbol
    end

    def visit!(q : QReturnDecrement)
      symbol = symbol(q.target)

      emit Opcode::SYM, symbol
      emit Opcode::DUP
      emit Opcode::TON
      emit Opcode::DEC
      emit Opcode::POP_ASSIGN, symbol
    end

    def visit!(q : QBinarySpread)
      visit(q.operand)
      emit Opcode::TOV
      emit Opcode::REDUCE, q.operator
    end

    def visit!(q : QLambdaSpread)
      stop = label?
      start = label?

      emit Opcode::VEC, 0
      visit(q.operand)
      emit Opcode::MAP_SETUP

      label start
      emit Opcode::MAP_ITER, stop
      visit(q.lambda)
      emit Opcode::MAP_APPEND
      emit Opcode::J, start

      label stop
      emit Opcode::POP
    end

    def visit!(q : QBlock)
      offset = chunk "<block>" do
        visit(q.body)

        emit Opcode::RET
      end

      emit Opcode::GOTO, offset
    end

    def visit!(q : QEnsure)
      visit(q.expression)

      emit Opcode::ENS
    end

    def visit!(q : QFun)
      given = uninitialized Int32
      arity = uninitialized Int32
      slurpy = uninitialized Bool
      params = uninitialized Array(String)
      target = uninitialized Int32

      repeat = false

      # Emit the 'given' values.
      q.params.zip?(q.given) do |_, given|
        if !given && !repeat
          emit Opcode::SYM, symbol("any", 0)
        elsif !given
          visit q.given.last
        elsif repeat = true
          visit given
        end
      end

      # Make the function visible.
      @context.let(q.name)

      @context.trace(q.tag, q.name) do
        @context.child do |nesting|
          target = chunk q.name do
            params = q.params
            onymous = params.reject("*")

            given = params.size
            arity = onymous.size
            slurpy = q.slurpy

            onymous.each do |parameter|
              @context.let(parameter)

              emit Opcode::POP_ASSIGN, symbol(parameter, nesting)
            end

            # Slurpies eat the rest of the stack's values. It
            # must, however, be proven that the slurpie (`*`)
            # is at the end of the function's parameters.
            if q.slurpy
              emit Opcode::REM_TO_VEC
              emit Opcode::POP_ASSIGN, symbol("rest", nesting)
            end

            visit q.body

            emit Opcode::RET
          end
        end
      end

      emit Opcode::FUN, VFunction.new(q.name, target, params, given, arity, slurpy)
    end

    # A note on infinite (and other) loops: they clear the
    # stack after each iteration. This prevents the stack
    # from flooding, if such a thing even occurs (e.g. `loop 1`).
    def visit!(q : QInfiniteLoop)
      start = label?

      label start
      visit(q.repeatee)
      emit Opcode::POP # q.body is QBlock => only 1 value exported
      emit Opcode::J, start
    end

    # Base loops, step loops and complex loops return false
    # if there were no iterations; otherwise, they return
    # the result of the last iteration.
    def visit!(q : QBaseLoop)
      stop = label?
      start = label?

      label start
      visit(q.base)
      emit Opcode::JIF, stop
      emit Opcode::TRY_POP # # previous q.repeatee
      visit(q.repeatee)
      emit Opcode::J, start

      label stop
      emit Opcode::FALSE_IF_EMPTY
    end

    # :ditto:
    def visit!(q : QStepLoop)
      stop = label?
      start = label?

      label start
      visit(q.base)
      emit Opcode::JIF, stop
      emit Opcode::TRY_POP # previous q.repeatee
      visit(q.repeatee)
      visit(q.step)
      emit Opcode::POP # q.step
      emit Opcode::J, start

      label stop
      emit Opcode::FALSE_IF_EMPTY
    end

    # :ditto:
    def visit!(q : QComplexLoop)
      stop = label?
      start = label?

      visit(q.start)
      emit Opcode::POP # q.start

      label start
      visit(q.base)
      emit Opcode::JIF, stop
      emit Opcode::TRY_POP # previous q.repeatee
      visit(q.repeatee)
      visit(q.step)
      emit Opcode::POP # q.step
      emit Opcode::J, start

      label stop
      emit Opcode::FALSE_IF_EMPTY
    end
  end
end
