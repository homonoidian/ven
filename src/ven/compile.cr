require "./suite/*"

module Ven
  # Provides the facilities to compile Ven quotes into a linear
  # sequence of Ven bytecode instructions.
  class Compiler < Suite::Visitor
    include Suite

    # Points to the chunk this Compiler is currently emitting into.
    @cp = 0
    # The closest surrounding function.
    @fun : VFunction?
    # A label pointing to the body of the closest surrounding loop.
    @loop : Label?
    # How many chunks exist prior to this compilation.
    @offset : Int32

    def initialize(@context : Context::Compiler, @file = "<unknown>", @offset = 0)
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
    #
    # The block may receive a computed target chunk pointer
    # - the chunk pointer where this new chunk will be at
    # after the compilation.
    private macro chunk!(name, &block)
      under @cp, being: @chunks.size do
        @chunks << Chunk.new(@file, {{name}})

        {% if block.args %}
          {{*block.args}} = @offset + @cp
        {% end %}

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

    # Makes a symbol *name*, trying to compute its nest first.
    # If failed to do this, fallbacks to `symbol`.
    private macro sym(name, nest = -1)
      %name = {{name}}

      if nest = @context.bound?(%name)
        mksym(%name, nest)
      else
        mksym(%name, {{nest}})
      end
    end

    # A shorthand for `VSymbol.new`.
    private macro mksym(name, nest = -1)
      VSymbol.new({{name}}, {{nest}})
    end

    # Emits the appropriate field gathering instructions
    # for *accessor*.
    private def field!(accessor : FAImmediate)
      emit Opcode::FIELD_IMMEDIATE, accessor.access
    end

    # :ditto:
    private def field!(accessor : FADynamic)
      visit(accessor.access)

      emit Opcode::FIELD_DYNAMIC
    end

    # :ditto:
    private def field!(accessor : FABranches)
      branches = accessor.access.items

      branches.each_with_index do |branch, index|
        emit Opcode::SWAP unless index == 0
        emit Opcode::DUP unless index == branches.size -  1

        if branch.is_a?(QAccessField)
          field! [FADynamic.new(branch.head)] + branch.tail
        elsif branch.is_a?(QSymbol)
          field! FAImmediate.new(branch.value)
        else
          field! FADynamic.new(branch)
        end
      end

      emit Opcode::VEC, branches.size
    end

    # Emits the appropriate field gathering instructions
    # for *accessors*.
    private def field!(accessors : FieldAccessors)
      accessors.each do |accessor|
        field!(accessor)
      end
    end

    # Emits the 'given' values.
    #
    # If there were no 'given' values, makes an `any` per
    # each parameter.
    #
    # If missing a few 'given' values, repeats the one that
    # was mentioned lastly.
    private def given!(params : Array(String), given : Quotes)
      repeat = false

      params.zip?(given) do |_, given_quote|
        if !given_quote && !repeat
          emit Opcode::ANY
        elsif !given_quote
          visit(given.last)
        elsif repeat = true
          visit(given_quote)
        end
      end
    end

    def visit!(q : QSymbol)
      emit Opcode::SYM, sym(q.value)
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
      finish = label

      visit(q.left)

      if finishable = q.operator == "and"
        emit Opcode::JIF_ELSE_POP, finish
      elsif finishable = q.operator == "or"
        emit Opcode::JIT_ELSE_POP, finish
      end

      visit(q.right)

      unless finishable
        return emit Opcode::BINARY, q.operator
      end

      label finish
    end

    def visit!(q : QAssign)
      visit(q.value)

      if q.global
        @context.bound(q.target)
      end

      emit Opcode::TAP_ASSIGN, sym(q.target)
    end

    def visit!(q : QBinaryAssign)
      target = sym(q.target)

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

    def visit!(q : QDies)
      finish = label
      handler = label

      emit Opcode::SETUP_DIES, handler
      visit(q.operand)
      emit Opcode::J, finish
      label handler
      emit Opcode::TRUE
      label finish
      emit Opcode::RESET_DIES
    end

    def visit!(q : QIntoBool)
      visit(q.operand)

      emit Opcode::TOB
    end

    def visit!(q : QReturnIncrement)
      emit Opcode::INC, sym(q.target)
    end

    def visit!(q : QReturnDecrement)
      emit Opcode::DEC, sym(q.target)
    end

    def visit!(q : QAccessField)
      visit(q.head)
      field!(q.tail)
    end

    def visit!(q : QReduceSpread)
      visit(q.operand)

      emit Opcode::REDUCE, q.operator
    end

    def visit!(q : QMapSpread)
      stop = label
      start = label

      unless q.iterative
        emit Opcode::VEC, 0
      end

      visit(q.operand)
      emit Opcode::TOV
      emit Opcode::MAP_SETUP
      label start
      emit Opcode::MAP_ITER, stop
      emit Opcode::POP_UPUT
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
      emit Opcode::TAP_UPUT

      if alt = q.alt
        emit Opcode::JIF, else_b
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
      @context.child do
        chunk! "<block>" do |target|
          visit(q.body)

          emit Opcode::RET
        end

        emit Opcode::GOTO, target
      end
    end

    def visit!(q : QEnsure)
      visit(q.expression)

      emit Opcode::ENS
    end

    def visit!(q : QFun)
      function = uninitialized VFunction

      given!(q.params, q.given)

      unless @context.bound?(q.name)
        @context.bound(q.name)
      end

      @context.trace(q.tag, q.name) do
        @context.child do
          chunk! q.name do |target|
            slurpy = q.slurpy
            params = q.params
            onymous = params.reject("*")

            function =
              VFunction.new(
                sym(q.name),
                target,
                params,
                q.params.size,
                onymous.size,
                slurpy)

            if slurpy
              emit Opcode::REST, onymous.size
            end

            onymous.reverse_each do |name|
              case name
              when "_"
                emit Opcode::POP_UPUT
              else
                emit Opcode::POP_ASSIGN, mksym(name, nest: -1)
              end
            end

            under @fun, being: function do
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
        emit Opcode::SYM, @fun.not_nil!.symbol
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

    def visit!(q : QReturnStatement)
      unless @fun
        die("statement 'return' outside of a function")
      end

      visit(q.value)
      emit Opcode::FORCE_RET
    end

    def visit!(q : QReturnExpression)
      unless @fun
        die("expression 'return' outside of a function")
      end

      visit(q.value)
      emit Opcode::SETUP_RET
    end

    def visit!(q : QBox)
      given!(q.params, q.given)

      unless @context.bound?(q.name)
        @context.bound(q.name)
      end

      symbol = sym(q.name)

      chunk! q.name do |target|
        @context.child do
          q.params.reverse_each do |param|
            emit Opcode::POP_ASSIGN, mksym(param, nest: -1)
          end

          q.namespace.each do |name, value|
            visit(value)

            emit Opcode::POP_ASSIGN, mksym(name, nest: -1)
          end

          emit Opcode::SYM, symbol
          emit Opcode::BOX_INSTANCE
          emit Opcode::RET
        end
      end

      # Here we use VFunction intentionally. Boxes and functions
      # are just too similar to make them distinct kinds of
      # payloads.
      emit Opcode::BOX, VFunction.new(
        symbol,
        target,
        q.params,
        q.params.size,
        q.params.size,
        false)

      emit Opcode::POP_ASSIGN, symbol
    end

    def visit!(q : QDistinct)
    end

    def visit!(q : QExpose)
    end

    # Compiles *quotes* under a `Context::Compiler` *context*.
    #
    # Returns the resulting chunks.
    def self.compile(context, quotes, file = "<unknown>", offset = 0)
      it = new(context, file, offset)
      it.visit(quotes)
      it.@chunks
    end
  end
end
