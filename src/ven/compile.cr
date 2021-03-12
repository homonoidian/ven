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

    def initialize(@file = "<unit>")
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

    # Defines a new chunk called *name*. Evaluates the block
    # within this new chunk. Returns the index that this chunk
    # will have in `@chunks`.
    private macro chunk(name, &)
      @chunks.unshift Chunk.new(@file, {{name}})

      begin
        {{yield}}
      ensure
        @chunks << @chunks.shift
      end

      @chunks.size - 1
    end

    # Returns the chunks produced by this compiler.
    def compile : Chunks
      @chunks.each do |chunk|
        chunk.delabel
      end

      @chunks
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

    def visit!(q : QBinary)
      visit q.left

      if q.operator.in?("and", "or")
        emit :GIF, :fail
        visit q.right
        emit :GIT, :end
        label :fail
        emit :FALSE
        label :end

        return true
      end

      visit q.right

      opcode =
        case q.operator
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

      # Emit a normalization (NOM) call first:
      emit :NOM, q.operator

      emit opcode
    end

    def visit!(q : QCall)
      visit q.callee
      visit q.args

      emit :CALL, q.args.size
    end

    def visit!(q : QAssign)
      visit q.value

      emit (q.global ? :GLOBAL : :LOCAL), q.target
    end

    def visit!(q : QEnsure)
      visit q.expression

      emit :ENS
    end

    def visit!(q : QIf)
      visit(q.cond)
      emit :GIF, :alt
      visit(q.suc)
      emit :G, :end
      label :alt
      q.alt ? visit(q.alt.not_nil!) : emit :FALSE
      label :end
    end

    def visit!(q : QFun)
      index = chunk q.name do
        # Assume the arguments are already on the stack.
        q.params.each do |parameter|
          emit :LOCAL, parameter
        end

        visit q.body

        emit :RET
      end

      emit :FUN, index
    end
  end
end
