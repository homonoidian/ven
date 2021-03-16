require "./suite/*"

module Ven
  # A compiler for a single Ven unit. Compiles the quotes it
  # is given into a sequence of `Chunk`s.
  # ```
  # c = Ven::Compiler.new
  # c.visit(Ven::Quote)
  # c.visit(Ven::Quote)
  # c.visit(Ven::Quote)
  # puts c.compile
  # ```
  class Compiler < Suite::Visitor(Bool)
    include Suite

    getter file : String

    def initialize(@file = "<unknown>")
      @chunks = [Chunk.new(@file, "<unit>")]
      @optimized = [] of String
      @funcname = [] of String
    end

    # Returns the first chunk.
    private macro lead
      @chunks.first
    end

    # Inserts an instruction into the first chunk of `@chunks`.
    # Assumes `q` is defined and is a Quote. Ensures *opcode*
    # is not nil.
    private macro emit(opcode, argument = nil)
      lead.add(q.tag.line, {{opcode}}.not_nil!, {{argument}})
    end

    # Safely emits an instruction without access to a `Quote`.
    private macro emit!(opcode, argument = nil)
      lead.add(lead.line?, {{opcode}}.not_nil!, {{argument}})
    end

    # Declares a label called *name* in the lead chunk.
    private macro label(name)
      lead.label({{name}})
    end

    # Returns a unique label.
    private macro label?
      Label.new
    end

    # Defines a new chunk called *name*. Evaluates the block
    # within this new chunk. Returns the index that this chunk
    # will have in `@chunks`.
    private macro chunk(name, meta = nil, &)
      @chunks.unshift Chunk.new(@file, {{name}},
        {% if meta %}
          meta = {{meta}}
        {% end %})

      begin
        {{yield}}
      ensure
        @chunks << @chunks.shift
      end

      @chunks.size - 1
    end

    # Finishes the process of compilation and returns the
    # resulting chunks.
    def compile : Chunks
      @chunks.each do |chunk|
        chunk.delabel
      end

      @chunks
    end

    # Returns the opcode for a binary *operator*, or nil if
    # *operator* is not one of the supported binary operators.
    private def binary_opcode?(operator : String) : Symbol?
      case operator
      when "in" then :CEQV
      when "is" then :EQU
      when "<=" then :LTE
      when ">=" then :GTE
      when "<"  then :LT
      when ">"  then :GT
      when "+"  then :ADD
      when "-"  then :SUB
      when "*"  then :MUL
      when "/"  then :DIV
      when "&"  then :PEND
      when "~"  then :CONCAT
      when "x"  then :TIMES
      end
    end

    # Emits code that will access field via *accessor*. *opcode*
    # is the working opcode.
    private def field(accessor : SingleFieldAccessor, opcode = :FIELD)
      emit! :STR, accessor.field
      emit! opcode if opcode
    end

    # :ditto:
    private def field(accessor : DynamicFieldAccessor, opcode = :FIELD)
      field = accessor.field

      if field.is_a?(QSymbol)
        emit! :SYM_OR_TOS, field.value
      else
        visit field
      end

      emit! opcode if opcode
    end

    # Emits code that will access field via *accessor*. *opcode*
    # is ignored.
    private def field(accessor : MultiFieldAccessor, opcode = :FIELD)
      amount = accessor.field.size

      accessor.field.each_with_index do |part, index|
        unless index == 0
          emit! :UP
        end

        # Duplicates the head, which must at first be present
        # prior the call to `field`.
        unless index == accessor.field.size - 1
          emit! :DUP
        end

        field(part, opcode)
      end

      emit! :VEC, amount
    end

    def visit!(q : QSymbol)
      if q.value.in?(@optimized)
        emit :FAST_SYM, q.value
      elsif q.value.in?(@funcname)
        emit :FAST_SYM_TOP, q.value
      else
        emit :SYM, q.value
      end
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

      if q.operator.in?("and", "or")
        fail = label?
        end_ = label?

        if q.operator == "and"
          emit :GIFP, fail
        elsif q.operator == "or"
          emit :GITP, end_
        end

        visit q.right
        emit :GITP, end_

        label fail
        emit :FALSE

        label end_
      else
        visit q.right

        # Emit a normalization (NOM) call first:
        emit :NOM, q.operator

        emit binary_opcode?(q.operator)
      end
    end

    def visit!(q : QCall)
      visit q.callee
      visit q.args

      emit :CALL, q.args.size
    end

    def visit!(q : QAssign)
      visit q.value

      emit (q.global ? :GLOBAL_PUT : :LOCAL_PUT), q.target
    end

    def visit!(q : QBinaryAssign)
      # STACK:
      emit :SYM, q.target
      # STACK: target-value
      visit q.value
      # STACK: target-value value
      emit :DUP
      # STACK: target-value value value-dup
      emit :UP2
      # STACK: value-dup target-value value
      emit :NOM, q.operator
      # STACK: value-dup target-value value
      emit :UP
      # STACK: value-dup value target-value
      emit binary_opcode?(q.operator)
      # STACK: value-dup binary-result
      emit :LOCAL, q.target
      # STACK: value-dup
    end

    def visit!(q : QIntoBool)
      visit q.value
      emit :TOB
    end

    def visit!(q : QReturnIncrement)
      emit :SYM, q.target
      emit :DUP
      emit :TON
      emit :INC
      emit :LOCAL, q.target
    end

    def visit!(q : QReturnDecrement)
      emit :SYM, q.target
      emit :DUP
      emit :TON
      emit :DEC
      emit :LOCAL, q.target
    end

    def visit!(q : QAccessField)
      visit q.head

      q.path.each do |piece|
        field piece
      end
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

      q.params.zip?(q.given) do |_, given|
        if !given && !repeat
          emit :SYM, "any"
        elsif !given
          visit q.given.last
        elsif repeat = true
          visit given
        end
      end

      offset = chunk q.name, meta: FunMeta.new do
        params = q.params
        onymous = params.reject("*")
        meta.given = params.size
        meta.arity = onymous.size
        meta.slurpy = q.slurpy
        meta.params = params

        # Assume that the arguments are already on the stack
        # and there was an arity check.
        onymous.each do |parameter|
          emit :FAST_LOCAL, parameter
        end

        # Slurpies eat the remaining values on the stack. It
        # must, however, be proven that the slurpie (`*`) is
        # at the end of the function's parameters.
        if q.slurpy
          emit :REM_TO_VEC
          emit :FAST_LOCAL, "rest"
        end

        @optimized += onymous
        @funcname << q.name

        visit q.body

        @optimized.pop(onymous.size)
        @funcname.pop

        emit :RET
      end


      emit :FUN, offset
    end

    def visit!(q : QInfiniteLoop)
      start = label?
      label start
      visit q.body

      # Pop all values left from the body. This prevents
      # billions of loop iterations flooding the stack.
      emit :POP_ALL

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
      emit :POP_ALL
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
      emit :POP_ALL
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
      emit :POP_ALL
      visit q.base
      emit :GIF, end_
      emit :POP_ALL
      visit q.body
      visit q.step
      emit :POP
      emit :G, start

      label end_
      emit :FALSE_IF_EMPTY
    end
  end
end
