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

    # Currently, there are several levels of verbosity:
    #   - `0`: totally quiet;
    #   - `1`: only issue warnings (default);
    #   - `2`: totally verbose.
    getter verbosity = 2

    # Directories where this Master will search for '.ven'
    # files.
    getter homes : Array(String)

    # The distincts this Master imported.
    @imported = Set(Distinct).new

    # Initializes a new Master.
    #
    # *homes* is a list of directories where this Master will
    # search for '.ven' files. A new `Input` is created in
    # the repository for each such '.ven' file.
    #
    # A warning will be shown if one (or more) Ven file in
    # one (or more) home directory cannot be read (see
    # `verbosity`).
    def initialize(@homes = [Dir.current])
      @repository = [] of Input

      @homes.each do |home|
        # Gathering all Ven files may seem to be ineffective,
        # but it allows to abstract away from the file system.
        Dir["#{home}/**/*.ven"].each do |file|
          begin
            @repository << Input.new file, File.read(file)
          rescue error : ReadError
            warn "read error: #{error} (near #{file}:#{error.line})"
          end
        end
      end
    end

    # Prints a colorized *warning*, with respect to
    # `verbosity`.
    def warn(warning : String)
      if @verbosity >= 1
        puts "#{"[warning]".colorize(:yellow)} #{warning}"
      end
    end

    # Prints a colorized debug *message*, with respect to
    # `verbosity`.
    def debug(message : String)
      if @verbosity >= 2
        puts "#{"[debug]".colorize(:blue)} #{message}"
      end
    end

    # Imports a distinct *expose*.
    #
    # The behavioral output of this method is based on all
    # `Input`s having a common context (through class vars,
    # that is; see `Input`).
    def import(expose : Distinct)
      debug "import #{expose}"

      if expose.in?(@imported)
        return debug "#{expose} already imported"
      end

      @repository.each do |input|
        next unless distinct = input.distinct

        debug "trying '#{input.file}'"

        if distinct.in?(@imported)
          next debug "#{distinct} already imported"
        end

        # If an input's distinct starts with *expose*, run
        # that input in the common context.
        if distinct[0, expose.size]? == expose
          debug "success: importing #{distinct}"

          input.run
        end

        # Add the input that we actually imported.
        @imported << distinct
      end

      # Now, add the umbrella (maybe, and maybe not; Set will
      # take care though).
      @imported << expose
    end

    # Reads, compiles and executes *source* under the name
    # *file* under this Master.
    def load(file : String, source : String)
      input = Input.new(file, source)
      input.exposes.each { |expose| import(expose) }
      input.run
    end

    def to_s(io)
      io << "master with " << @imported.size << " imports"
    end
  end
end
