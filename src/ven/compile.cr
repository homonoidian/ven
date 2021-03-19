require "./suite/*"

module Ven
  # A visitor that transforms a tree of quotes into a linear
  # sequence of instructions.
  class Compiler < Suite::Visitor(Bool)
    include Suite

    def initialize(@context : Context::Compiler, @file = "<unknown>")
      @cursor = 0
      @chunks = [Chunk.new(@file, "<unit>")]
    end

    # Raises a traceback-ed compile-time error. Ensures all
    # traces are cleared afterwards.
    def die(message : String)
      traces = @context.traces.dup

      unless traces.last?.try(&.name) == "<unit>"
        traces << Trace.new(@last.tag, "<unit>")
      end

      raise CompileError.new(traces, message)
    end

    # Returns the chunk at cursor.
    private macro lead
      @chunks[@cursor]
    end

    # Declares a label in the lead chunk.
    private macro label(name)
      lead.label({{name}})
    end

    # Requests a new, unique label.
    private macro label?
      Label.new
    end

    # Emits an instruction into the lead chunk.
    #
    # Ensures *opcode* is not nil.
    private macro emit(opcode, argument = nil)
      lead.add(@last.tag.line, {{opcode}}.not_nil!, {{argument}})
    end

    # Defines a new chunk, *name*, and evaluates the block
    # within it.
    #
    # If *meta*, an instance of `Meta`, is given, it is exposed
    # under the *meta* variable inside the block.
    #
    # Returns the chunk cursor for this new chunk.
    private macro chunk(name, meta = nil, &)
      %chunk =
        {% if meta %}
          Chunk.new(@file, {{name}}, meta = {{meta}})
        {% else %}
          Chunk.new(@file, {{name}})
        {% end %}

      @chunks << %chunk

      # Make *%chunk* the lead chunk for the time the block
      # executes. This makes `emit` emit instructions into
      # it.
      old, @cursor = @cursor, @chunks.size - 1

      begin
        {{yield}}

        @cursor
      ensure
        @cursor = old
      end
    end

    # Looks up or dies.
    private macro lookup(name)
      @context.lookup(%name = {{name}}) || die("symbol not found: #{%name}")
    end

    # A shorthand for `Entry.new(...)`.
    private macro entry(name, nesting = nil)
      {% if nesting %}
        Entry.new({{name}}, {{nesting}})
      {% else %}
        Entry.new(%name = {{name}}, lookup %name)
      {% end %}
    end

    def visit!(q : QSymbol)
      emit :SYM, entry(q.value)
    end

    def visit!(q : QNumber)
      emit :NUM, q.value
    end

    def visit!(q : QString)
      emit :STR, q.value
    end

    def visit!(q : QRegex)
      emit :PCRE, q.value
    end

    def visit!(q : QVector)
      visit q.items

      emit :VEC, q.items.size
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
        when "not" then :TOIB
        when "&"
          return emit :VEC, 1
        end

      emit opcode
    end

    def visit!(q : QBinary)
      visit q.left
      visit q.right

      emit :BINARY, q.operator
    end

    def visit!(q : QAssign)
      nesting = @context.assign(q.target, q.global)
      visit q.value
      emit :SET_TAP, entry(q.target, nesting)
    end

    def visit!(q : QCall)
      visit q.callee
      visit q.args

      emit :CALL, q.args.size
    end

    def visit!(q : QIntoBool)
      visit q.value

      emit :TOB
    end

    def visit!(q : QReturnIncrement)
      nesting = entry(q.target)

      emit :SYM, nesting
      emit :DUP
      emit :TON
      emit :INC
      emit :SET, nesting
    end

    def visit!(q : QReturnDecrement)
      nesting = entry(q.target)

      emit :SYM, nesting
      emit :DUP
      emit :TON
      emit :DEC
      emit :SET, nesting
    end

    def visit!(q : QLambdaSpread)
      stop = label?
      start = label?

      visit q.operand
      emit :TOV
      emit :SETUP_MAP, stop

      label start
      emit :MAP_ITER
      visit q.lambda
      emit :TOV
      emit :PEND
      emit :G, start

      label stop
    end

    def visit!(q : QEnsure)
      visit q.expression

      emit :ENS
    end

    def visit!(q : QIf)
      fail = label?
      end_ = label?

      visit q.cond
      emit :GIFP, fail

      visit q.suc
      emit :G, end_

      label fail

      if alt = q.alt
        visit alt
      else
        emit :FALSE
      end

      label end_
    end

    def visit!(q : QFun)
      repeat = false
      offset = uninitialized Int32

      # Emit the 'given' values.
      q.params.zip?(q.given) do |_, given|
        if !given && !repeat
          emit :SYM, Entry.new("any", 0)
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
          offset = chunk q.name, meta: Metadata::Function.new do
            params = q.params
            onymous = params.reject("*")

            meta.given = params.size
            meta.arity = onymous.size
            meta.slurpy = q.slurpy
            meta.params = params

            onymous.each do |parameter|
              @context.let(parameter)

              emit :SET_POP, entry(parameter, nesting)
            end

            # Slurpies eat the rest of the stack's values. It
            # must, however, be proven that the slurpie (`*`)
            # is at the end of the function's parameters.
            if q.slurpy
              emit :REM_TO_VEC
              emit :SET, entry("rest", nesting)
            end

            visit q.body

            emit :RET
          end
        end
      end

      emit :FUN, offset
    end

    def visit!(q : QInfiniteLoop)
      start = label?
      label start
      visit q.body

      # Pop all values left from the body. This prevents
      # billions of loop iterations flooding the stack.
      emit :CLEAR

      emit :G, start
    end

    def visit!(q : QBaseLoop)
      start = label?
      end_ = label?

      label start

      # Loops return the value produced by the last iteration,
      # if there was at least one, or false (which is returned
      # by the q.base, causing the loop to end). GIF pops the
      # base, leaving only the result of the last iteration,
      # if any.
      visit q.base
      emit :GIF, end_
      emit :CLEAR
      visit q.body
      emit :G, start

      label end_
      emit :FALSE_IF_EMPTY
    end

    def visit!(q : QStepLoop)
      start = label?
      end_ = label?

      label start
      visit q.base
      emit :GIF, end_
      emit :CLEAR
      visit q.body
      visit q.step
      emit :POP
      emit :G, start

      label end_
      emit :FALSE_IF_EMPTY
    end

    def visit!(q : QComplexLoop)
      start = label?
      end_ = label?

      visit q.start

      label start
      visit q.pres
      emit :CLEAR
      visit q.base
      emit :GIF, end_
      emit :CLEAR
      visit q.body
      visit q.step
      emit :POP
      emit :G, start

      label end_
      emit :FALSE_IF_EMPTY
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
