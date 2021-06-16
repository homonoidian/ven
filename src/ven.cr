require "fancyline"
require "commander"

require "./lib"

module Ven
  # Ven command line interface builds an `Orchestra` and an
  # `Enquiry`, and uses them to run a program from a file,
  # interactive prompt, or distinct.
  class CLI
    include Suite

    # The path where the REPL history file can be found.
    HISTORY = ENV["VEN_HISTORY"]? || Path.home / ".ven_history"

    # The regex matching a REPL command word. Command words
    # begin a REPL command (see `command`).
    COMMAND_WORD = /\\\w+/

    # These represent the flags. Look into their corresponding
    # helps in the Commander scaffold to know what they're for.
    @quit = true
    @final = "evaluate"
    @result = false
    @measure = false
    @serialize = false

    # The orchestra and Enquiry cannot be initialized at this
    # point; they are never used before they've been initialized
    # anyways. That's why these `uninitialized`s are safe (but
    # are they?)
    @enquiry = uninitialized Enquiry
    @orchestra = uninitialized Orchestra

    def initialize
      Colorize.on_tty_only!
    end

    # Prints an error according to the following template:
    # `[*embraced*] *message*`. If `@quit` is true, quits
    # with status 1 afterwards.
    private def err(embraced : String, message : String)
      puts "#{"[#{embraced}]".colorize(:red)} #{message}"
      exit(1) if @quit
    end

    # Dies of an *error* (see `err`).
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
      err("error", error.to_s)
    end

    # Displays the *quotes*. Returns nothing.
    def display(quotes : Quotes)
      puts Detree.detree(quotes)
    end

    # Displays the *chunks*. Returns nothing.
    def display(chunks : Chunks)
      puts chunks.join("\n\n")
    end

    # Displays the *timetable*. Returns nothing.
    def display(timetable : Machine::Timetable)
      timetable.each do |cidx, stats|
        puts "chunk #{cidx}".colorize.underline

        stats.each do |ip, report|
          amount = report[:amount]
          duration = report[:duration]

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

          # Choose the correct unit. Use color to show hotspots.
          duration, unit =
            if (ns = duration.total_nanoseconds) < 1000
              {ns.colorize.green, "ns"}
            elsif (us = duration.total_microseconds) < 1000
              {us.colorize.yellow, "us"}
            elsif (ms = duration.total_milliseconds) < 1000
              {ms.colorize.light_red, "ms"}
            else
              {duration.total_seconds.colorize.cyan, "sec"}
            end

          puts "@#{ip}| #{report[:instruction]} [#{amount} time(s), took #{duration} #{unit}]"
        end
      end
    end

    # Displays the *value*. Returns nothing.
    def display(value)
      puts value if @result && value
    end

    # Evaluates the *source* using the active orchestra.
    #
    # *file* is the filename by which the source will
    # be identified.
    #
    # Respects the chosen final step. Returns the result that
    # this step produced.
    def eval(file : String, source : String)
      program = @orchestra.from(source, file, @enquiry, run: false)

      {% begin %}
        case @final
        # Evaluate is an edge-case because it needs coop
        # not only with Program, but with runtime Orchestra
        # too. Nothing else does.
        when "evaluate"
          program.run(@orchestra.pool)
        {% for step, order in Program::Step.constants %}
          {% unless step.stringify == "Evaluate" %}
            # To illustrate this, let's look what this will
            # expand into given `step = Program::Step::Compile`.
            #
            # ```
            # when "compile"
            #   program
            #     .then(Program::Step::Read)
            #     .then(Program::Step::Transform)
            #     .then(Program::Step::Compile)
            # ```
            when {{step.stringify.downcase}}
              program
                # Including *step*!
                {% for predecessor in Program::Step.constants[0..order] %}
                  .then(Program::Step::{{predecessor}})
                {% end %}
              # `result_for` will return the result of the
              # given step, if it ever was performed.
              program.result_for(Program::Step::{{step}})
          {% end %}
        {% end %}
        else
          die("invalid final step: #{@final}")
        end
      {% end %}
    end

    # Evaluates the *source* using the active orchestra.
    #
    # *file* is the filename by which the source will
    # be identified.
    #
    # `run` is a front-end to `eval`, in that it beautifies
    # the errors and implements various supplement features
    # (measurements, timetable display, etc.)
    #
    # Returns nothing.
    def run(file : String, source : String)
      result = nil

      # Measure the duration of full `eval`. This duration
      # is what is shown by '-m'.
      duration = Time.measure do
        result = eval(file, source)
      end

      # Although they have very similar names, `@enquiry.measure`
      # is much more thorough (it's per-instruction) than
      # `@measure`. They can be combined.
      if @enquiry.measure
        # We're sure timetable's there at this point.
        display(@enquiry.timetable)
      end

      if @serialize
        unless @final.in?("read", "transform")
          die("the result of the final step is not serializable yet")
          # Die does not break us out of the function!
          return
        end
        # TODO: serialize all possible results: chunks,
        # models, etc.
        puts result.as(Quotes).to_pretty_json
      else
        display(result)
      end

      if @measure
        puts "[took #{duration.total_microseconds}us]".colorize.bold
      end
    rescue e : VenError
      die(e)
    end

    # Processes a REPL command.
    def command(head : String, tail : String)
      case {head, tail}
      when {"help", _}
        puts <<-END
        \\COMMAND [TAIL]

        Available commands:
          \\help: show this
          \\serialize: serialize TAIL
          \\deserialize: deserialize TAIL
          \\deserialize_detree: deserialize & detree TAIL
          \\lserq: deserialize quotes from file TAIL, and detree
          \\run_serq: deserialize quotes from file TAIL, and run
          \\context: serialize context (TAIL = reader, compiler, machine)
        END
      when {"serialize", _}
        puts Program.new(tail).step(Program::Step::Read).quotes.to_json
      when {"deserialize", _}
        puts Quotes.from_json(tail)
      when {"deserialize_detree", _}
        puts Detree.detree(Quotes.from_json(tail))
      when {"lserq", _}
        puts Detree.detree(Quotes.from_json(File.read(tail)))
      when {"run_lserq", _}
        puts run(tail, Detree.detree(Quotes.from_json(File.read(tail))))
      when {"context", "reader"}
        puts @orchestra.hub.reader.to_pretty_json
      when {"context", "compiler"}
        puts "compiler context TODO"
      when {"context", "machine"}
        puts "machine context TODO"
      else
        die("Invalid REPL command: '#{head}'.")
      end
    end

    # Launches the read-eval-print loop.
    def repl
      fancy = Fancyline.new

      fancy.display.add do |ctx, line, yielder|
        if line.starts_with?(COMMAND_WORD)
          # Highlight the REPL instruction, given a line that
          # starts with one.
          yielder.call ctx, line.sub(COMMAND_WORD) { $0.colorize.yellow }
        else
          yielder.call ctx, highlight(line)
        end
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
        elsif source.starts_with?(COMMAND_WORD)
          # Interpret the rest of the input as a REPL command,
          # and not as Ven code.
          next command($0.lstrip("\\"), source[$0.size..].strip)
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
              break # CTRL+D pressed.
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
        cmd.use = "ven"
        cmd.long = Ven::VERSION

        # Unmapped flags are passed to the program.
        cmd.ignore_unmapped_flags = true

        cmd.flags.add do |flag|
          flag.name = "port"
          flag.short = "-p"
          flag.long = "--port"
          flag.default = 12879
          flag.description = "Set the referent Inquirer port."
        end

        cmd.flags.add do |flag|
          flag.name = "inspect"
          flag.short = "-i"
          flag.long = "--inspect"
          flag.default = false
          flag.description = "Enable instruction-by-instruction inspector."
        end

        cmd.flags.add do |flag|
          flag.name = "measure"
          flag.short = "-m"
          flag.long = "--measure"
          flag.default = false
          flag.description = "Show total execution time."
        end

        cmd.flags.add do |flag|
          flag.name = "timetable"
          flag.short = "-M"
          flag.default = false
          flag.description = "Show per-instruction execution time (timetable)."
        end

        cmd.flags.add do |flag|
          flag.name = "final"
          flag.short = "-j"
          flag.long = "--just"
          flag.default = "evaluate"
          flag.description = "Can be: read, transform, optimize, compile, evaluate."
        end

        cmd.flags.add do |flag|
          flag.name = "result"
          flag.short = "-r"
          flag.long = "--result"
          flag.default = false
          flag.description = "Show result of the final step."
        end

        cmd.flags.add do |flag|
          flag.name = "optimize"
          flag.short = "-O"
          flag.long = "--optimize"
          flag.default = 1
          flag.description = "Set the amount of optimization passes."
        end

        cmd.flags.add do |flag|
          flag.name = "fast-interrupt"
          flag.long = "--fast-interrupt"
          flag.default = false
          flag.description = "Disable domestic SIGINT handling."
        end

        cmd.flags.add do |flag|
          flag.name = "test-mode"
          flag.short = "-t"
          flag.long = "--test"
          flag.default = false
          flag.description = "Disignore ensure tests."
        end

        cmd.flags.add do |flag|
          flag.name = "serialize"
          flag.short = "-s"
          flag.long = "--serialize"
          flag.default = false
          flag.description = "Serialize final step."
        end

        cmd.run do |options, arguments|
          port = options.int["port"].as Int32

          @orchestra = Orchestra.new(port)
          @orchestra.test_mode = options.bool["test-mode"]

          @final = options.string["final"]
          @result = options.bool["result"]
          @measure = options.bool["measure"]
          @serialize = options.bool["serialize"]

          @enquiry = Enquiry.new
          @enquiry.measure = options.bool["timetable"]
          @enquiry.inspect = options.bool["inspect"]
          @enquiry.optimize = options.int["optimize"].to_i * 8
          @enquiry.fast_interrupt = options.bool["fast-interrupt"]
          @enquiry.test_mode = options.bool["test-mode"]

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
            # have access to ARGS, including any side library.
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
