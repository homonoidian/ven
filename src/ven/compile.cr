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

    # A shorthand for `DSymbol.new(...)`.
    private macro symbol(name, nesting = nil)
      {% if nesting %}
        DSymbol.new({{name}}, {{nesting}})
      {% else %}
        DSymbol.new(%name = {{name}}, lookup %name)
      {% end %}
    end

    # Assigns a *symbol*. Returns the resulting `DSymbol`.
    private macro assign(symbol, global)
      %symbol = {{symbol}}
      %global = {{global}}
      %nesting = @context.assign({{symbol}}, {{global}})

      symbol(%symbol, %nesting)
    end

    def visit!(q : QSymbol)
      emit :SYM, symbol(q.value)
    end

    def visit!(q : QNumber)
      emit :NUM, q.value
    end

    def visit!(q : QString)
      emit :STR, q.value
    end

    def visit!(q : QVector)
      emit :VEC, visit(q.items)
    end

    def visit!(q : QUPop)
      emit :UPOP
    end

    def visit!(q : QURef)
      emit :UREF
    end

    def visit!(q : QUnary)
      visit q.operand

      opcode =
        case q.operator
        when "+" then :TON
        when "-" then :NEG
        when "~" then :TOS
        when "#" then :LEN
        when "&" then :TOV
        when "not" then :TOIB
        end

      emit opcode
    end

    def visit!(q : QBinary)
      visit([q.left, q.right])

      emit :BINARY, q.operator
    end

    def visit!(q : QAssign)
      visit(q.value)

      emit :TAP_ASSIGN, assign(q.target, q.global)
    end

    def visit!(q : QCall)
      visit(q.callee)

      emit :CALL, visit(q.args)
    end

    def visit!(q : QIntoBool)
      visit(q.value)

      emit :TOB
    end

    def visit!(q : QReturnIncrement)
      symbol = symbol(q.target)

      emit :SYM, symbol
      emit :DUP
      emit :TON
      emit :INC
      emit :SET, symbol
    end

    def visit!(q : QReturnDecrement)
      symbol = symbol(q.target)

      emit :SYM, symbol
      emit :DUP
      emit :TON
      emit :DEC
      emit :SET, symbol
    end

    def visit!(q : QBinarySpread)
      visit(q.operand)
      emit :TOV
      emit :REDUCE, q.operator
    end

    def visit!(q : QLambdaSpread)
      stop = label?
      start = label?

      emit :VEC, 0
      visit(q.operand)
      emit :MAP_SETUP

      label start
      emit :MAP_ITER, stop
      visit(q.lambda)
      emit :MAP_APPEND
      emit :J, start

      label stop
      emit :POP
    end

    def visit!(q : QEnsure)
      visit(q.expression)

      emit :ENS
    end

    def visit!(q : QFun)
      repeat = false
      offset = uninitialized Int32
      function = DFunction.new(q.name)

      # Emit the 'given' values.
      q.params.zip?(q.given) do |_, given|
        if !given && !repeat
          emit :SYM, symbol("any", 0)
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
          function.chunk = chunk q.name do
            params = q.params
            onymous = params.reject("*")

            function.given = params.size
            function.arity = onymous.size
            function.slurpy = q.slurpy
            function.params = params

            onymous.each do |parameter|
              @context.let(parameter)

              emit :POP_ASSIGN, symbol(parameter, nesting)
            end

            # Slurpies eat the rest of the stack's values. It
            # must, however, be proven that the slurpie (`*`)
            # is at the end of the function's parameters.
            if q.slurpy
              emit :REM_TO_VEC
              emit :POP_ASSIGN, symbol("rest", nesting)
            end

            visit q.body

            emit :RET
          end
        end
      end

      emit :FUN, function
    end

    # Finalizes the process of compilation. Returns the
    # resulting chunks.
    def compile : Chunks
      @chunks.each do |chunk|
        chunk.delabel
      end

      @chunks
    end
  end
end
