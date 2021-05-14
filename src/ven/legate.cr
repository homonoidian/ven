module Ven
  class Legate
    # `Machine`: whether to run the inspector.
    property inspect = false
    # `Machine`: whether to build the timetable.
    property measure = false
    # `Program`: the amount of optimize passes.
    property optimize = 8

    # `Machine`: the resulting timetable (if `measure` enabled).
    property timetable = Ven::Machine::Timetable.new
  end
end
