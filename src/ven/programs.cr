require "digest/sha256"

require "./suite/*"

module Ven
  # Multiple Ven programs, and a second-tier high level
  # manager.
  #
  # It is an abstraction over a list of `Program`s. Its sole
  # purpose is to implement the semantics of `distinct` and
  # `expose`, that is, to run right programs at right times
  # and in right places.
  #
  # Basic usage:
  # ```
  # ps = Programs.new
  #
  # p1 = ps.add("distinct p1; x = 2")
  # p2 = ps.add("distinct p2; y = 3")
  # p3 = ps.add("expose p1; expose p2; x + y")
  #
  # puts ps.run(p3) # 5 : Num
  # ```
  class Programs
    include Suite

    # A mapping of PIDs to Programs.
    getter programs = {} of String => Program

    # Makes a new programs manager.
    #
    # *hub* is the common context hub that all programs
    # will use.
    def initialize(@hub = Context::Hub.new)
      # All programs are executed in a common chunk pool.
      @pool = Chunks.new
      # A mapping of distincts to PIDs.
      @scopes = {} of Distinct => Array(String)
    end

    # Adds a new program to this programs manager.
    #
    # *source* is the source code of the new program, and
    # *file* is its filename (or unit name) (optional).
    #
    # Returns the pid (program id) that this program was
    # assigned.
    #
    # Pids are used throughout the other methods of `Programs`
    # to refer to a specific program.
    def add(source : String, file : String = "untitled")
      # PID is a hash of filename (or unit name) and source.
      pid = Digest::SHA256.hexdigest(file + source)

      # Add the program to the repository.
      @programs[pid] = program = Program.new(source, file, @hub)

      distinct = program.distinct || [pid]

      # Register the distinct of this program, and bind it to PID.
      # Make sure we're not duplicating (as @scopes[<scope>] is
      # more like an ordered set).
      if @scopes.has_key?(distinct) && !pid.in?(@scopes[distinct])
        @scopes[distinct] << pid
      else
        @scopes[distinct] = [pid]
      end

      pid
    end

    # Returns the program with pid *pid*.
    #
    # Raises if found no such program (i.e., *pid* is invalid).
    def get(pid : String)
      @programs[pid]? || raise "no program with pid '#{pid}'"
    end

    # Researches which distinct scopes should be evaluated
    # before the program with pid *pid* for it to run correctly.
    #
    # Returns a joint (linear) list of unique PIDs of those
    # scopes.
    private def relate(pid : String)
      status = false
      result = [] of String

      get(pid).exposes.each do |expose|
        @scopes.each_with_index do |pair, index|
          scope, subscribers = pair

          # scope.starts_with?(expose)
          if status ||= scope[0, expose.size]? == expose
            # Reject *pid* to avoid infinite recursion (I guess):
            result += subscribers.reject(pid)
          elsif !status && index == @scopes.size - 1
            raise ExposeError.new(expose.join ".")
          end
        end
      end

      result.uniq!
    end

    # Runs the program with pid *pid*.
    #
    # First, resolves the dependencies of *pid*, and runs them
    # in the appropriate order. Only then does it run *pid*
    # itself.
    #
    # Returns the result of running *pid*.
    #
    # Raises if found no program with pid *pid* (i.e., *pid*
    # is invalid).
    def run(pid : String)
      result = nil

      (relate(pid) + [pid]).each do |runnable|
        result = get(runnable).run(@pool)
      end

      result
    end

    # Deletes the program with pid *pid*.
    #
    # Raises if found no such program (i.e., *pid* is invalid).
    def del(pid : String)
      get(pid) && @programs.delete(pid)
    end
  end
end
