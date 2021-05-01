module Ven
  # An abstraction over an implicit collection of `Input`s.
  #
  # Implements Ven module system (e.g., `distinct` and `expose`).
  #
  # Note that all files in the current directory (CD), as well
  # as the files of `homes`, are made into `Input`s. But only
  # those that were `expose`d are compiled and executed.
  #
  # ```
  # master = Master.new
  # master.load("a", "x = 1 + 1")
  # master.load("b", "y = 2 + x")
  # master.load("c", "say(x, y)") # STDOUT: 2 \n 4
  # ```
  class Master
    include Suite

    # Directories where this Master will search for '.ven' files.
    getter homes : Array(String)
    # The timetable produced by the latest `load`.
    getter timetable : Machine::Timetable?

    # The amount of optimization passes.
    property passes = 8
    # See `Input.measure`.
    property measure = false
    # See `Input.inspect`.
    property inspect = false
    # Currently, there are several levels of verbosity:
    #   - `0`: totally quiet;
    #   - `1`: only issue warnings (default);
    #   - `2`: issue warnings and debug prints.
    property verbosity = 1

    # The files that this Master has already exposed.
    @exposed = Set(String).new

    def initialize(@homes = [Dir.current])
      @repository = [] of Input
    end

    # Prints a colorized *warning* if `verbosity` allows.
    def warn(warning : String)
      if @verbosity >= 1
        puts "#{"[warning]".colorize(:yellow)} #{warning}"
      end
    end

    # Prints a colorized debug *message* if `verbosity` allows.
    def debug(message : String)
      if @verbosity >= 2
        puts "#{"[debug]".colorize(:blue)} #{message}"
      end
    end

    # Searches for '.ven' files in this Master's homes.
    #
    # A new `Input` is added to the repository for each '.ven'
    # file. A warning will be shown if it cannot be read (if
    # allowed by `verbosity`).
    def gather
      @homes.each do |home|
        debug("gather in #{home}")

        Dir["#{home}/**/[^_]*.ven"].each do |file|
          debug("gather #{file}")

          begin
            @repository << Input.new(file, File.read(file), @passes)
          rescue error : ReadError
            warn "read error: #{error} (near #{file}:#{error.line})"
          end
        end
      end
    end

    # Imports a distinct *expose*.
    #
    # This method will only work if all `Input`s are being
    # evaluated in a common environment.
    def import(expose : Distinct)
      success = false

      debug("import #{expose}")

      @repository.each do |input|
        next unless distinct = input.distinct

        debug("trying '#{input.file}'")

        # If an input's distinct starts with *expose*, run
        # that input in the common context.
        if distinct[0, expose.size]? == expose
          success = true

          if input.file.in?(@exposed)
            next debug("#{distinct} already exposed")
          end

          debug("found: importing #{distinct}")

          # Expose everything the input that we expose itself
          # exposes. Make sure not to import itself in the
          # process.
          input.exposes.each do |subexpose|
            import(subexpose) unless expose == subexpose
          end

          input.run

          # Remember the file that was exposed.
          @exposed << input.file
        end
      end

      unless success
        raise ExposeError.new("could not expose '#{expose.join(".")}'")
      end
    end

    # Reads, compiles and executes *source* under filename *file*.
    def load(file : String, source : String)
      input = Input.new(file, source, @passes)

      input.exposes.each { |expose| import(expose) }
      input.measure = @measure
      input.inspect = @inspect

      result = input.run

      # For some reason, `Input.run(&)` beauty won't export
      # @timetable like `Machine.start(&)` (see `eval`).
      @timetable = input.timetable

      result
    end

    def to_s(io)
      io << "master with " << @exposed.size << " imports"
    end
  end
end
