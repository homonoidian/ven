module Ven::Suite
  # The list of all opcodes.
  #
  # Sectioning matters for further execution. Opcodes must be
  # added to the appropriate sections.
  enum Opcode
    # Opcodes that take no payload.

    POP             = 16
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
    POP_UPUT
    TAP_UPUT
    UPOP
    UREF
    CLEAR
    RET
    MAP_SETUP
    MAP_APPEND
    FALSE_IF_EMPTY
    FIELD_DYNAMIC
    RESET_DIES
    FORCE_RET
    SETUP_RET
    ANY
    BOX_INSTANCE
    TEST_TITLE
    TEST_ASSERT
    QUEUE
    FORCE_RET_QUEUE
    TOR_BL # beginless
    TOR_EL # endless
    TOM

    # Opcodes that take a static payload.

    NUM             = 128
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
    REST
    TEST_SHOULD
    ACCESS
    MAP

    # Opcodes that take a jump payload.

    J            = 512
    JIT
    JIF
    MAP_ITER
    JIT_ELSE_POP
    JIF_ELSE_POP
    SETUP_DIES

    # Opcodes that take a symbol payload.

    SYM        = 1024
    POP_ASSIGN
    TAP_ASSIGN
    INC
    DEC

    # Opcodes that take a function payload.

    FUN    = 2048
    BOX
    LAMBDA

    # Returns the kind of payload an instruction takes (`:static`,
    # `:jump`, `:symbol`, `:function`, or nil).
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

    # Returns whether this opcode always puts one value onto
    # the operand stack without popping any values or producing
    # side effects.
    def puts_one?
      self.in?(
        DUP,
        SYM,
        NUM,
        STR,
        PCRE,
        TRUE,
        FALSE,
        UPOP,
        UREF,
        ANY)
    end
  end
end
