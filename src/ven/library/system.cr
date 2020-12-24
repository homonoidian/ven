module Ven::Library
  class System < Component::Extension
    fun! "put", str : Str do |machine|
      print str.value

      str
    end

    fun! "get" do |machine|
      unless input = gets
        machine.die("'get': end-of-input")
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