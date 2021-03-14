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

    def visit!(q : QSymbol)
      emit :SYM, q.value
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

    def visit!(q : QBinary)
      visit q.left

      if q.operator.in?("and", "or")
        fail = label?
        end_ = label?

        if q.operator == "and"
          emit :GIF, fail
        elsif q.operator == "or"
          emit :GIT, end_
        end

        visit q.right
        emit :GIT, end_

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

    def visit!(q : QCall)
      visit q.callee
      visit q.args

      emit :CALL, q.args.size
    end

    def visit!(q : QAssign)
      visit q.value

      emit (q.global ? :GLOBAL_PUT : :LOCAL_PUT), q.target
    end

    def visit!(q : QEnsure)
      visit q.expression

      emit :ENS
    end

    def visit!(q : QIf)
      fail = label?
      end_ = label?

      visit q.cond
      emit :GIF, fail

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
          emit :LOCAL, parameter
        end

        # Slurpies eat the remaining values on the stack. It
        # must, however, be proven that the slurpie (`*`) is
        # at the end of the function's parameters.
        if q.slurpy
          emit :REM_TO_VEC
          emit :LOCAL, "rest"
        end

        visit q.body

        emit :RET
      end

      emit :FUN, offset
    end
  end
end
