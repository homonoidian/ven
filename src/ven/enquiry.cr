module Ven
  # Enquiry allows communication between Ven's different
  # levels of abstraction.
  #
  # It convoys properties from the very heights of machinery
  # (i.e., `Orchestra`) down to `Program`, `Machine`, etc.
  #
  # The recipient can also send some data back to the top.
  class Enquiry
    # TO `Machine`: whether to run the inspector.
    property inspect = false
    # TO `Machine`: whether to build the timetable.
    property measure = false
    # TO `Program`: the amount of optimize passes.
    property optimize = 8
    # TO `Compiler`: if true, enables test mode (i.e., disignores
    # 'ensure' tests).
    property test_mode = false

    # FROM `Machine`: the timetable (if had `measure` enabled).
    property timetable = Ven::Machine::Timetable.new
  end
end
