module Ven
  # Legate convoys various configurations from the heights
  # of abstraction (i.e., `Orchestra`) down, to `Program`,
  # `Machine`, or anyone else willing.
  #
  # It does the same in the opposite direction; i.e., one can
  # also *send* data with `Legate` back to the top.
  class Legate
    # `Machine`: whether to run the inspector.
    property inspect = false
    # `Machine`: whether to build the timetable.
    property measure = false
    # `Program`: the amount of optimize passes.
    property optimize = 8
    # `Machine`: if true, the system handles SIGINT interrupt
    # (and your program runs faster); if false, Ven handles
    # SIGINT interrupt.
    property fast_interrupt = false
    # `Compiler`: if true, enables test mode (i.e., disignores
    # 'ensure' tests).
    property test_mode = false

    # `Machine`: returns the resulting timetable (if had
    # `measure` enabled).
    property timetable = Ven::Machine::Timetable.new
  end
end
