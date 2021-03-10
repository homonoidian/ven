require "./suite/*"

module Ven
  class Compiler < Suite::Visitor(Int32)
    include Suite

    def initialize(file : String)
      @chunks = [Chunk.new(file)]
    end

    # Returns the latest chunk.
    def chunk
      @chunks.last
    end

    # Appends an instruction to the current chunk. Assumes
    # `q` is defined and is a Quote.
    private macro emit(opcode, argument = nil)
      chunk.add(q.tag.line, {{opcode}}.not_nil!, {{argument}})
    end

    # Evaluates the block 'between' instruction indices *left*
    # and *right*. Inside the block, *delta* is defined. It is
    # a difference between the indices *right* and *left*.
    private macro between(left, right, &)
      delta = {{right}} - {{left}}
      %took = @chunks.last.take(delta)
      {{yield}}
      @chunks.last << %took
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
      visit(q.items)

      emit :VEC, q.items.size
    end

    def visit!(q : QURef)
      emit :UREF
    end

    def visit!(q : QUPop)
      emit :UPOP
    end

    def visit!(q : QUnary)
      visit(q.operand)

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
      left  = visit(q.left)
      right = visit(q.right)

      if q.operator == "and"
        between(left, right) do |delta|
          # Jump after `right` (delta) and JOIT (at
          # delta + 1) to FALSE (at delta + 2) if left
          # is false.
          emit :JOIF, delta + 2
        end

        # Jump to the instr. after FALSE if right is true:
        emit :JOIT, 2
        emit :FALSE
      elsif q.operator == "or"
        between(left, right) do |delta|
          emit :JOIT, delta + 2
        end
      else
        opcode =
          case q.operator
          when "in" then :CEQV
          when "is" then :EQU
          when "<=" then :LTE
          when ">=" then :GTE
          when "<" then :LT
          when ">" then :GT
          when "+" then :ADD
          when "-" then :SUB
          when "*" then :MUL
          when "/" then :DIV
          when "&" then :PEND
          when "~" then :CONCAT
          when "x" then :TIMES
          end

        # Emit a normalization (NOM) call first:
        emit :NOM, q.operator

        emit opcode
      end
    end

    def visit!(q : QCall)
      visit(q.callee)
      visit(q.args)

      emit :INK, q.args.size
    end

    def visit!(q : QAssign)
      visit(q.value)

      emit :SET, q.target
    end

    def visit!(q : QEnsure)
      visit(q.expression)

      emit :ENS
    end

    # A `Suite::Visitor.visit`, but returns the amount of
    # instructions in the current chunk.
    def visit(quote)
      super(quote)

      chunk.size
    end
  end
end
