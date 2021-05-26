require "fancyline"
require "commander"

require "./lib"

module Ven
  # Ven command line interface builds an `Orchestra` and a
  # `Legate`, and uses them to run a program from a file,
  # interactive prompt, or a particular distinct.
  class CLI
    include Suite

    # Contains the path to Ven REPL history file.
    HISTORY = ENV["VEN_HISTORY"]? || Path.home / ".ven_history"

    # These represent the flags. Look into their corresponding
    # helps in the Commander scaffold to know what they are for.
    @quit = true
    @final = "eval"
    @result = false
    @measure = false

    # The orchestra and legate cannot be initialized at
    # this point, and they cannot be used before they've
    # been initialized. That's why these `uninitialized`s
    # are safe (are they?)
    @legate = uninitialized Legate
    @orchestra = uninitialized Orchestra

    def initialize
      Colorize.on_tty_only!
    end

    # Prints an error according to the following template:
    # `[*embraced*] *message*`.
    #
    # Decides whether to quit by looking at `@quit`.
    #
    # Quits with status 1 if decided to quit.
    private def err(embraced : String, message : String)
      puts "#{"[#{embraced}]".colorize(:red)} #{message}"
      exit(1) if @quit
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
      err("expose error", e.message || "bad expose")
    end

    # :ditto:
    private def die(error)
      err("general error", error.to_s)
    end

    # Displays the given *quotes*.
    #
    # Returns nothing.
    def display(quotes : Quotes)
      puts Detree.detree(quotes)
    end

    # Displays the given *chunks*.
    #
    # Returns nothing.
    def display(chunks : Chunks)
      chunks.each { |chunk| puts chunk }
    end

    # Displays the given *timetable*.
    #
    # Returns nothing.
    def display(timetable : Machine::Timetable)
      timetable.each do |cidx, stats|
        puts "chunk #{cidx}".colorize.underline

        stats.each do |ip, report|
          amount = report[:amount]
          duration = report[:duration].total_microseconds

          amount =
            if amount < 100
              amount.colorize.green
            elsif amount < 1_000
              amount.colorize.yellow
            elsif amount < 10_000
              amount.colorize.light_red
            else
              amount.colorize.red
            end

          duration =
            if duration < 100
              "#{duration}us".colorize.green
            elsif duration < 1_000
              "#{duration}us".colorize.yellow
            elsif duration < 10_000
              "#{duration}us".colorize.light_red
            else
              "#{duration}us".colorize.red
            end

          puts "@#{ip}| #{report[:instruction]} [#{amount} time(s), took #{duration}]"
        end
      end
    end

    # Displays the given *value*.
    #
    # Returns nothing.
    def display(value)
      puts value if @result && value
    end

    #
    #
    #
    def run(file : String, source : String)
      result  = nil
      program = @orchestra.from(source, file, @legate, run: false)

      # Measure the duration of the whole thing.
      duration = Time.measure do
        case @final
        when "read"
          result = program
            .step(Program::Step::Read)
            .quotes
        when "compile"
          result = program
            .step(Program::Step::Read)
            .then(Program::Step::Compile)
            .chunks
        when "optimize"
          result = program
            .step(Program::Step::Read)
            .then(Program::Step::Compile)
            .then(Program::Step::Optimize)
            .chunks
        when "eval"
          result = program.run(@orchestra.pool)
        else
          die("invalid final step: #{@final}")
        end
      end

      # Although they have very similar names, `@legate.measure`
      # is much more thorough (per-instruction) than `@measure`.
      # And they can be combined (for seeing the total time)!
      if @legate.measure
        # We're sure it's there at this point.
        display(@legate.timetable)
      end

      display(result)

      # Again, we show **the total time** it took the program
      # to execute here.
      if @measure
        puts "[took #{duration.total_microseconds}us]".colorize.bold
      end
    rescue e : VenError
      die(e)
    end

    # Launches the read-eval-print loop.
    def repl
      fancy = Fancyline.new

      fancy.display.add do |ctx, line, yielder|
        yielder.call ctx, highlight(line)
      end

      if File.exists?(HISTORY) && File.file?(HISTORY) && File.readable?(HISTORY)
        File.open(HISTORY, "r") do |io|
          fancy.history.load(io)
        end
      end

      puts "[Ven #{VERSION}]",
           "Hit CTRL+D to exit."

      loop do
        begin
          source = fancy.readline(" #{"~>".colorize(:dark_gray)} ").try(&.strip)
        rescue Fancyline::Interrupt
          next puts
        end

        if source.nil? # CTRL+D pressed.
          break
        elsif source.empty?
          next
        end

        loop do
          # As ugly as it seems, it'll work for now.
          if !(source.count('(') != 0 && source.count('(') > source.count(')')) &&
             !(source.count('[') != 0 && source.count('[') > source.count(']')) &&
             !(source.count('{') != 0 && source.count('{') > source.count('}'))
            break
          end

          begin
            unless snippet = fancy.readline("... ").try(&.strip)
              # CTRL+D pressed.
              break
            end

            source += "\n#{snippet}"
          rescue Fancyline::Interrupt
            break
          end
        end

        run("interactive", source)
      end

      File.open(HISTORY, "w") do |io|
        fancy.history.save(io)
      end

      puts "Bye bye!"
      exit 0
    end

    # Highlights a *snippet* of Ven code.
    private def highlight(snippet)
      offset = 0
      result = ""

      loop do
        case pad = snippet[offset..]
        when .starts_with? Ven.regex_for(:STRING)
          result += $0.colorize.yellow.to_s
        when .starts_with? Ven.regex_for(:SYMBOL)
          if Reader::KEYWORDS.any?($0)
            result += $0.colorize.blue.to_s
          else
            result += $0.colorize.bold.toggle(@orchestra.hub[$0]?).to_s
          end
        when .starts_with? Ven.regex_for(:REGEX)
          result += $0.colorize.yellow.to_s
        when .starts_with? Ven.regex_for(:NUMBER)
          result += $0.colorize.magenta.to_s
        when .starts_with? Ven.regex_for(:IGNORE)
          result += $0.colorize.dark_gray.to_s
        when .empty?
          break
        else
          # Pass over unknown characters.
          result += snippet[offset]
          offset += 1
          next
        end

        offset += $0.size
      end

      result
    end

    # Returns the Commander command line interface for Ven.
    def main
      Commander::Command.new do |cmd|
        cmd.use  = "ven"
        cmd.long = Ven::VERSION

        # Unmapped flags will go to the program.
        cmd.ignore_unmapped_flags = true

        cmd.flags.add do |flag|
          flag.name        = "port"
          flag.short       = "-p"
          flag.long        = "--port"
          flag.default     = 12879
          flag.description = "Set the referent Inquirer port."
        end

        cmd.flags.add do |flag|
          flag.name        = "inspect"
          flag.short       = "-i"
          flag.long        = "--inspect"
          flag.default     = false
          flag.description = "Enable instruction-by-instruction inspector."
        end

        cmd.flags.add do |flag|
          flag.name        = "measure"
          flag.short       = "-m"
          flag.long        = "--measure"
          flag.default     = false
          flag.description = "Enable execution time output."
        end

        cmd.flags.add do |flag|
          flag.name        = "timetable"
          flag.short       = "-M"
          flag.default     = false
          flag.description = "Enable per-instruction execution time output (timetable)."
        end

        cmd.flags.add do |flag|
          flag.name        = "final"
          flag.short       = "-j"
          flag.long        = "--just"
          flag.default     = "eval"
          flag.description = "Set the final step (read, compile, optimize, eval)"
        end

        cmd.flags.add do |flag|
          flag.name        = "result"
          flag.short       = "-r"
          flag.long        = "--result"
          flag.default     = false
          flag.description = "Print the result of the final step."
        end

        cmd.flags.add do |flag|
          flag.name        = "optimize"
          flag.short       = "-O"
          flag.long        = "--optimize"
          flag.default     = 1
          flag.description = "Set the amount of optimization passes."
        end

        cmd.flags.add do |flag|
          flag.name        = "fast-interrupt"
          flag.long        = "--fast-interrupt"
          flag.default     = false
          flag.description = "Enable system SIGINT handling (makes your program run faster)."
        end

        cmd.run do |options, arguments|
          port = options.int["port"].as Int32

          @orchestra = Orchestra.new(port)

          @final = options.string["final"]
          @result = options.bool["result"]
          @measure = options.bool["measure"]

          @legate = Legate.new
          @legate.measure = options.bool["timetable"]
          @legate.inspect = options.bool["inspect"]
          @legate.optimize = options.int["optimize"].to_i * 8
          @legate.fast_interrupt = options.bool["fast-interrupt"]

          if arguments.empty?
            # Do not quit after errors:
            @quit = false
            # Do print the result:
            @result = true
            # Fly!
            repl()
          elsif arguments.size >= 1
            file = arguments.first

            # Provide the unmapped flags/remaining arguments
            # to the orchestra. It's a bit risky, as some user-
            # defined flags may interfere with this CLI's.
            #
            # Note that **all** programs of the orchestra will
            # have access to these very arguments, including
            # any exposed library.
            @orchestra.hub.machine["ARGS"] = Vec.from(arguments[1...], Str)

            if File.exists?(file) && File.file?(file) && File.readable?(file)
              run File.expand_path(file), File.read(file)
            elsif !@orchestra.isolated && file =~ /^(\w[\.\w]*[^\.])$/
              # If there is no such file, try to look if it's
              # a distinct.
              candidates = @orchestra.files_for? file.split('.')

              if candidates.empty?
                die("no such distinct: '#{file}'")
              elsif candidates.size > 1
                die("too many (#{candidates.size}) candidates for '#{file}'")
              end

              # Trust Inquirer that *candidate* is readable,
              # is a file, is an absolute path, etc.
              run candidate = candidates.first, File.read(candidate)
            else
              die("there is no readable file or distinct named '#{file}'")
            end
          end
        end
      end
    end

    # Starts Ven command line interface from the given *argv*.
    def self.start(argv)
      Commander.run(new.main, argv)
    end
  end
end

Ven::CLI.start(ARGV)
