module Ven::Suite
  # The list of all opcodes.
  #
  # NOTE: sectioning matters. Please add opcodes to the
  # appropriate sections.
  enum Opcode
    # Opcodes that take no payload.
    POP = 16
    POP2
    SWAP
    TRY_POP
    DUP
    TON
    TOS
    TOB
    TOIB
    TRUE
    FALSE
    TOV
    NEG
    LEN
    ENS
    UPUT
    UPOP
    UREF
    CLEAR
    RET
    INC
    DEC
    MAP_SETUP
    MAP_APPEND
    REM_TO_VEC
    FALSE_IF_EMPTY
    FIELD_DYNAMIC

    # Opcodes that take a static payload.
    NUM = 128
    STR
    VEC
    PCRE
    GOTO
    CALL
    REDUCE
    BINARY
    BINARY_ASSIGN
    FIELD_IMMEDIATE
    NEXT_FUN

    # Opcodes that take a jump payload.
    J = 512
    JIT
    JIF
    MAP_ITER
    JIT_ELSE_POP
    JIF_ELSE_POP

    # Opcodes that take a symbol payload.
    SYM = 1024
    POP_ASSIGN
    TAP_ASSIGN

    # Opcodes that take a function payload.
    FUN = 2048

    # Returns the kind of payload an instruction takes, or
    # nil if it does not take any.
    def payload
      case value
      when 128...512
        :static
      when 512...1024
        :jump
      when 1024...2048
        :symbol
      when 2048..
        :function
      end
    end

     # Returns whether this opcode puts exactly one value on
     # the operand stack **no matter what**, and consumes none.
    def puts_one?
      self.in?(DUP, SYM, NUM, STR, PCRE, TRUE, FALSE, UPOP, UREF)
    end
  end
end
