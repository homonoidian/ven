require "./suite/*"

module Ven
  # Provides the facilities to compile Ven quotes into a linear
  # sequence of Ven bytecode instructions.
  class Compiler < Suite::Visitor
    include Suite

    # Points to the chunk this Compiler is currently
    # emitting into.
    @cp = 0

    # A label pointing to the body of the nearmost surrounding
    # loop. This is mostly useful for `next loop`.
    @loop : Label?

    # The payload vehicle & nest of the nearmost surrounding
    # function. This is mostly useful for `next fun`.
    @fun : {VFunction, Int32}?

    def initialize(@context : Context::Compiler, @file = "<unknown>")
      @chunks = [Chunk.new(@file, "<unit>")]
    end

    # Raises a compile-time error, providing it the traceback.
    def die(message : String)
      traces = @context.traces.dup

      unless traces.last?.try(&.name) == "<unit>"
        traces << Trace.new(@last.tag, "<unit>")
      end

      raise CompileError.new(traces, message)
    end

    # Makes *target* be *value* while in the block.
    private macro under(target, being value, &block)
      %old, {{target}} = {{target}}, {{value}}

      begin
        {{yield}}
      ensure
        {{target}} = %old
      end
    end

    # Returns the chunk at the *cursor* (hereinafter chunk-of-emission).
    private macro chunk(at cursor = @cp)
      @chunks[{{cursor}}]
    end

    # Introduces a new chunk under the name *name* and with
    # the filename of this Compiler.
    #
    # In the block, makes the chunk-of-emission be this new
    # chunk.
    private macro chunk!(name, &block)
      @chunks << Chunk.new(@file, {{name}})

      under @cp, being: @chunks.size - 1 do
        {{yield}}
      end
    end

    # Returns a new label.
    private macro label
      Label.new
    end

    # In the chunk-of-emission, introduces a new blob of
    # instructions under a *label*.
    private macro label(label)
      chunk.label({{label}})
    end

    # Emits an instruction into the chunk-of-emission.
    #
    # Additionally, ensures *opcode* is not nil.
    private macro emit(opcode, argument = nil)
      chunk.add({{opcode}}.not_nil!, {{argument}}, @last.tag.line)
    end

    # Makes a new symbol vehicle (see `VSymbol`).
    #
    # If provided with a *nest*, makes it the new symbol's
    # nest. Otherwise, uses the context to determine the
    # nest. If couldn't determine, makes the symbol's nest
    # nil.
    private macro symbol(name, nest = nil)
      {% if nest %}
        VSymbol.new({{name}}, {{nest}})
      {% else %}
        VSymbol.new(%name = {{name}}, @context.lookup %name)
      {% end %}
    end

    # Emulates an assignment to *symbol*. Returns the resulting
    # symbol vehicle (`VSymbol`).
    private macro assign(symbol, global = false)
      %symbol = {{symbol}}
      %nest = @context.assign(%symbol, {{global}})
      symbol(%symbol, %nest)
    end

    # Returns the raw result of this compiler's work: an
    # array of unoptimized, unstitched chunks.
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

    def visit!(q : QRegex)
      emit Opcode::PCRE, q.value
    end

    def visit!(q : QVector)
      visit(q.items)
      emit Opcode::VEC, q.items.size
    end

    def visit!(q : QUPop)
      emit Opcode::UPOP
    end

    def visit!(q : QURef)
      emit Opcode::UREF
    end

    def visit!(q : QUnary)
      visit(q.operand)

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
      visit(q.left)

      if q.operator == "and"
        alt = label
        end_ = label

        emit Opcode::JIF, alt
        visit(q.right)
        emit Opcode::JIT_ELSE_POP, end_
        label alt
        emit Opcode::FALSE
        label end_
      elsif q.operator == "or"
        end_ = label

        emit Opcode::JIT_ELSE_POP, end_
        visit(q.right)
        emit Opcode::JIT_ELSE_POP, end_
        emit Opcode::FALSE
        label end_
      else
        visit(q.right)
        emit Opcode::BINARY, q.operator
      end
    end

    def visit!(q : QAssign)
      visit(q.value)
      emit Opcode::TAP_ASSIGN, assign(q.target, q.global)
    end

    def visit!(q : QBinaryAssign)
      target = symbol(q.target)

      visit(q.value)
      emit Opcode::SYM, target
      emit Opcode::BINARY_ASSIGN, q.operator
      emit Opcode::POP_ASSIGN, target
    end

    def visit!(q : QCall)
      visit(q.callee)
      visit(q.args)
      emit Opcode::CALL, q.args.size
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

    # Emits the appropriate field gathering instructions for
    # a field accessor *accessor*.
    private def field(accessor : FAImmediate)
      emit Opcode::FIELD_IMMEDIATE, accessor.access
    end

    # :ditto:
    private def field(accessor : FADynamic)
      visit(accessor.access)
      emit Opcode::FIELD_DYNAMIC
    end

    # :ditto:
    private def field(accessor : FAMulti)
      items = accessor.access.items

      items.each_with_index do |item, index|
        emit Opcode::SWAP unless index == 0
        emit Opcode::DUP unless index == items.size -  1

        if item.is_a?(QAccessField)
          field [FADynamic.new(item.head)] + item.tail
        elsif item.is_a?(QSymbol)
          field FAImmediate.new(item.value)
        else
          field FADynamic.new(item)
        end
      end

      emit Opcode::VEC, items.size
    end

    # Emits the appropriate field gathering instructions for
    # each field accessor of *accessors*.
    private def field(accessors : FieldAccessors)
      accessors.each do |accessor|
        field(accessor)
      end
    end

    def visit!(q : QAccessField)
      visit(q.head)
      field(q.tail)
    end

    def visit!(q : QReduceSpread)
      visit(q.operand)
      emit Opcode::TOV
      emit Opcode::REDUCE, q.operator
    end

    def visit!(q : QMapSpread)
      stop = label
      start = label

      unless q.iterative
        emit Opcode::VEC, 0
      end

      visit(q.operand)
      emit Opcode::MAP_SETUP
      label start
      emit Opcode::MAP_ITER, stop
      emit Opcode::UPUT
      visit(q.operator)

      if q.iterative
        emit Opcode::POP
      else
        emit Opcode::MAP_APPEND
      end

      emit Opcode::J, start

      label stop

      unless q.iterative
        emit Opcode::POP
      end
    end

    def visit!(q : QIf)
      finish = label
      else_b = label

      visit(q.cond)

      if alt = q.alt
        emit Opcode::JIF_ELSE_POP, else_b
        visit(q.suc)
        emit Opcode::J, finish
        label else_b
        visit(alt)
      else
        emit Opcode::JIF_ELSE_POP, finish
        visit(q.suc)
      end

      label finish
    end

    def visit!(q : QBlock)
      chunk! "<block>" do
        visit(q.body)
        emit Opcode::RET
      end

      # `chunk` always appends:
      emit Opcode::GOTO, @chunks.size - 1
    end

    def visit!(q : QEnsure)
      visit(q.expression)
      emit Opcode::ENS
    end

    def visit!(q : QFun)
      function = uninitialized VFunction

      # Emit the 'given' values.
      #
      # If there were no 'given' values, make an `any` per
      # each function parameter.
      #
      # Otherwise, if missing 'given' values, repeat the
      # latest mentioned one.

      repeat = false

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
        @context.child do |nest|
          chunk! q.name do
            slurpy = q.slurpy
            params = q.params
            onymous = params.reject("*")

            function =
              VFunction.new(q.name,
                @cp,
                params,
                q.params.size,
                onymous.size,
                slurpy)

            onymous.each do |parameter|
              emit Opcode::POP_ASSIGN, assign(parameter)
            end

            # Slurpies eat the rest of the stack's values. It
            # must, however, be proven that the slurpie (`*`)
            # is at the end of the function's parameters.
            if slurpy
              emit Opcode::REM_TO_VEC
              emit Opcode::POP_ASSIGN, assign("rest")
            end

            # The scope of `nest - 1` encloses this function.
            under @fun, being: { function, nest - 1 } do
              visit q.body
            end

            emit Opcode::RET
          end
        end
      end

      emit Opcode::FUN, function
    end

    def visit!(q : QInfiniteLoop)
      start = label

      label start

      under @loop, being: start do
        visit(q.repeatee)
      end

      emit Opcode::POP
      emit Opcode::J, start
    end

    # Base loops, step loops and complex loops return false
    # if there were no iterations; otherwise, they return
    # the result of the last iteration.
    def visit!(q : QBaseLoop)
      stop = label
      start = label

      label start
      visit(q.base)
      emit Opcode::JIF, stop

      # Pop previous q.repeatee, if any.
      # XXX: BUG-PRONE if loop becomes an expression.
      emit Opcode::TRY_POP

      under @loop, being: start do
        visit(q.repeatee)
      end

      emit Opcode::J, start

      label stop
      emit Opcode::FALSE_IF_EMPTY
    end

    # :ditto:
    def visit!(q : QStepLoop)
      stop = label
      start = label

      label start
      visit(q.base)
      emit Opcode::JIF, stop
      emit Opcode::TRY_POP

      under @loop, being: start do
        visit(q.repeatee)
      end

      visit(q.step)
      emit Opcode::POP # q.step
      emit Opcode::J, start

      label stop
      emit Opcode::FALSE_IF_EMPTY
    end

    # :ditto:
    def visit!(q : QComplexLoop)
      stop = label
      start = label

      visit(q.start)
      emit Opcode::POP
      label start
      visit(q.base)
      emit Opcode::JIF, stop
      emit Opcode::TRY_POP

      under @loop, being: start do
        visit(q.repeatee)
      end

      visit(q.step)
      emit Opcode::POP # q.step
      emit Opcode::J, start
      label stop
      emit Opcode::FALSE_IF_EMPTY
    end

    def visit!(q : QNext)
      args, scope = q.args, q.scope

      if @fun && scope.in?("fun", nil)
        function, nest = @fun.not_nil!

        emit Opcode::SYM, symbol(function.name, nest)
        visit(args)
        emit Opcode::NEXT_FUN, args.size
      elsif @loop && scope.in?("loop", nil)
        unless args.empty?
          die("'next loop' arguments are currently illegal")
        end

        emit Opcode::J, @loop.not_nil!
      else
        die("'next' outside of a loop or a function")
      end
    end
  end
end
