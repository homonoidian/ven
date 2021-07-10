module Ven
  # Enquiry allows communication between Ven's different
  # levels of abstraction.
  #
  # It convoys properties from the very heights of machinery
  # (i.e., `Orchestra`) down to `Program`, `Machine`, etc.
  #
  # The recipient can also send some data back to the top.
  class Enquiry
    # TO ALL: whether to broadcast relevant data.
    property broadcast = false

    # Builds a Category-Payload (set by *category* and *input*
    # correspondingly) JSON object and broadcasts it if
    # broadcast mode is enabled.
    def broadcast(category : String, input)
      if @broadcast && @receiver
        @receiver.not_nil!.call({
          "Category" => category,
          "Payload"  => input,
        }.to_json)
      end
    end

    # Whenever data is broadcast, yields *procedure* with
    # that data verbatim.
    def receive(&procedure : String ->)
      @receiver = procedure
    end

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
