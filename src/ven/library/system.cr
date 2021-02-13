module Ven::Library
  class System < Component::Extension
    FANCY = Fancyline.new

    fun! "put", str : Str do |machine|
      print str.value

      str
    end

    fun! "get", prompt : Str do |machine|
      begin
        unless input = FANCY.readline(prompt.value, history: false)
          machine.die("'get': end-of-input")
        end
      rescue Fancyline::Interrupt
        machine.die("'get': interrupted")
      end

      Str.new(input)
    end

    # A temporary solution to measure time.
    fun! "time" do |machine|
      Num.new(Time.monotonic.nanoseconds)
    end

    def load
      defun "put"
      defun "get"
      defun "time"
    end
  end
end
