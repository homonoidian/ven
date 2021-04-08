require "fancyline"
require "option_parser"

require "./ven/**"

module Ven
  VERSION = "0.1.1-rev11"

  # Help messages describing various commands/switches/etc.
  module Help
    HELP = "Display this help and exit"
    RESULT = "Display result after execution"
    VERSION = "Display Ven version and exit"
    MEASURE = "Display time measurements after execution"
    OPTIMIZE = "Amount of optimize passes (default: 1, actually LEVEL * 8)"
    DISASSEMBLE = "Display bytecode before execution"
    VERBOSE_EXPOSE = "Set expose verbosity (0 [no], 1 [warn, default], 2 [debug+warn])"
  end

  class CLI
    include Suite

    # All files & REPL inputs go to and through this Master.
    @master = Master.new

    # Flags and options important to this CLI.
    @quit = true
    @result = false

    # Prints *message* and quits with status 0.
    private def quit(message : String)
      puts message

      exit 0
    end

    # Prints an error according to the following template:
    # `[*embraced*] *message*`.
    #
    # Decides whether to quit by looking at `@quit`.
    #
    # Quits with status 1 if decided to quit.
    private def err(embraced : String, message : String)
      puts "#{"[#{embraced}]".colorize(:red)} #{message}"

      if @quit
        exit(1)
      end
    end

    # Dies of an *error*.
    #
    # See `err`.
    private def die(error e : ReadError)
      err("read error", "#{e.message} (in #{e.file}:#{e.line}, near '#{e.lexeme}')")
    end

    # :ditto:
    private def die(error e : CompileError)
      err("compile error", "#{e.message}\n#{e.traces.join("\n")}")
    end

    # :ditto:
    private def die(error e : RuntimeError)
      err("runtime error", "#{e.message}\n#{e.traces.join("\n")}")
    end

    # :ditto:
    private def die(error e : InternalError)
      err("internal error", e.message.not_nil!)
    end

    # :ditto:
    private def die(error e : ExposeError)
      err("expose error", e.message.not_nil!)
    end

    # :ditto:
    private def die(error)
      err("general error", error.to_s)
    end

    # Runs *source* under the filename *file*, respecting `@result`.
    #
    # Rescues all `VenError`s and forwards them to `die`.
    def run(file : String, source : String)
      result = @master.load(file, source)

      if @result && !result.nil?
        puts result
      end
    rescue error : VenError
      die(error)
    end

    # Makes sure that *file* is a file and can be opened &
    # executed, and, if so, executes it. Otherwise, dies.
    def open(file : String)
      unless File.exists?(file) && File.file?(file) && File.readable?(file)
        die("'#{file}' does not exist or is not a readable file")
      end

      @master.gather

      run file, File.read(file)
    end

    # Launches the read-eval-print loop.
    def repl
      fancy = Fancyline.new

      puts "[Ven #{VERSION}]",
           "Hit CTRL+D to exit."

      @master.gather

      loop do
        begin
          source = fancy
            .readline(" #{"~>".colorize(:dark_gray)} ")
            .try(&.strip)
        rescue Fancyline::Interrupt
          next puts
        end

        if source.nil? # CTRL+D was pressed:
          exit(0)
        elsif source.empty?
          next
        end

        run("interactive", source)
      end
    end

    # Parses the command line arguments and dispatches to
    # the appropriate entry method.
    def parse
      OptionParser.parse do |me|
        me.banner = "Usage: ven [options] [argument]"

        me.separator("\nSwitches:")

        me.on("-m", "--measure", Help::MEASURE) { @master.measure = true }
        me.on("-d", "--disassemble", Help::DISASSEMBLE) { @master.disassemble = true }
        me.on("-r", "--print-result", Help::RESULT) { @result = true }

        me.on("-e LEVEL", "--verbose-expose=LEVEL", Help::VERBOSE_EXPOSE) do |level|
          @master.verbosity = level.to_i
        end

        me.on("-O LEVEL", Help::OPTIMIZE) do |level|
          @master.passes = level.to_i * 8
        end

        me.separator("\nGeneral options:")

        me.on("-h", "--help", Help::HELP) { quit me.to_s }
        me.on("-v", "--version", Help::VERSION) { quit VERSION }

        me.unknown_args do |args|
          case args.size
          when 0
            # `repl` requires a couple of flags to be set
            # before it actually runs.
            @quit = false
            @result = true

            repl
          when 1
            open(args.first)
          else
            die("unrecognized arguments: #{args.join(", ")}")
          end
        end

        me.invalid_option do |option|
          die("unrecognized option: #{option}")
        end
      end
    end

    def self.start
      new.parse
    end
  end
end

Ven::CLI.start
