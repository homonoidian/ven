require "fancyline"
require "commander"

require "./ven/**"

module Ven
  VERSION = "0.1.1-rev11"

  class CLI
    include Suite

    # Whether to quit after a Ven error.
    @quit = true
    # The step that we will stop on.
    @step = :eval
    # All files & REPL inputs go to and through this Master.
    @master = Master.new
    # Whether to display the result.
    @result = false
    # The amount of optimization passes.
    @passes = 8
    # Whether we run isolated.
    @isolated = false

    def initialize
      Colorize.on_tty_only!
    end

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
      err("expose error", "#{e.message} #{@isolated ? "(isolated)" : ""}")
    end

    # :ditto:
    private def die(error)
      err("general error", error.to_s)
    end

    # Displays *quotes*.
    def display(quotes : Quotes)
      puts Detree.detree(quotes)
    end

    # Displays *chunks*.
    def display(chunks : Chunks)
      chunks.each { |chunk| puts chunk }
    end

    # Displays *timetable*.
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

    # Displays *entity*.
    def display(entity)
      puts entity if @result && entity
    end

    # Runs *source* named *file* up to the step requested by
    # the user (orelse eval), and `display`s whatever that
    # step returns.
    def run(file : String, source : String)
      unless @step == :eval
        return display Input.run(file, source, until: @step, passes: @passes)
      end

      value = @master.load(file, source)
      display @master.timetable
      display value
    rescue error : VenError
      die(error)
    end

    # Makes sure that *file* is a file and can be opened &
    # executed, and, if so, executes it. Otherwise, dies.
    def open(file : String)
      unless File.exists?(file) && File.file?(file) && File.readable?(file)
        die("'#{file}' does not exist or is not a readable file")
      end

      unless @isolated
        @master.gather
      end

      run file, File.read(file)
    end

    # A tiny lexer that highlights a *snippet* of Ven code.
    private def highlight(snippet)
      offset = 0
      result = ""

      loop do
        case pad = snippet[offset..]
        when Reader::RX_REGEX
          result += $0.colorize.yellow.to_s
        when Reader::RX_SYMBOL
          if Reader::KEYWORDS.any?($0)
            result += $0.colorize.blue.to_s
          else
            result += $0.colorize.bold.toggle(Input.context[$0]?).to_s
          end
        when Reader::RX_STRING
          result += $0.colorize.yellow.to_s
        when Reader::RX_NUMBER
          result += $0.colorize.magenta.to_s
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

    # Launches the read-eval-print loop.
    def repl
      fancy = Fancyline.new

      fancy.display.add do |ctx, line, yielder|
        yielder.call ctx, highlight(line)
      end

      puts "[Ven #{VERSION}]",
           "Hit CTRL+D to exit."

      unless @isolated
        @master.gather
      end

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

    def parse
      Commander::Command.new do |cmd|
        cmd.use = "ven"
        cmd.long = VERSION

        cmd.flags.add do |flag|
          flag.name = "just"
          flag.short = "-j"
          flag.long = "--just"
          flag.default = "eval"
          flag.description = "Halt at a certain step (read, compile, optimize)."
        end

        cmd.flags.add do |flag|
          flag.name = "isolated"
          flag.short = "-i"
          flag.long = "--isolated"
          flag.default = false
          flag.description = "Do not look up other Ven files."
        end

        cmd.flags.add do |flag|
          flag.name = "result"
          flag.short = "-r"
          flag.long = "--result"
          flag.default = false
          flag.description = "Display the output of the final step."
        end

        cmd.flags.add do |flag|
          flag.name = "measure"
          flag.short = "-m"
          flag.long = "--measure"
          flag.default = false
          flag.description = "Display instruction timetable."
        end

        cmd.flags.add do |flag|
          flag.name = "optimize"
          flag.short = "-O"
          flag.long = "--optimize"
          flag.default = 1
          flag.description = "Set the amount of optimization passes."
        end

        cmd.flags.add do |flag|
          flag.name = "inspect"
          flag.short = "-s"
          flag.long = "--inspect"
          flag.default = false
          flag.description = "Enable step-by-step evaluation inspector."
        end

        cmd.flags.add do |flag|
          flag.name = "verbose"
          flag.short = "-v"
          flag.long = "--verbose"
          flag.default = 1
          flag.description = "Set master verbosity (0: quiet, 1: warn, 2: warn + debug)."
        end

        cmd.run do |options, arguments|
          @result = options.bool["result"]

          @master.passes = @passes = options.int["optimize"].as(Int32) * 8
          @master.inspect = options.bool["inspect"]
          @master.measure = options.bool["measure"]
          @master.verbosity = options.int["verbose"].as(Int32)

          case just = options.string["just"]
          when "eval"
            # pass
          when "read"
            @step = :read
          when "compile"
            @step = :compile
          when "optimize"
            @step = :optimize
          else
            die("'just': invalid step: #{just}").not_nil!
          end

          # We are isolated if: (a) `-i` was passed; or (b)
          # we are never going to evaluate.
          @isolated = options.bool["isolated"] || @step != :eval

          case arguments.size
          when 0
            @quit = false
            @result = true
            repl
          when 1
            open(arguments.first)
          else
            die("illegal arguments: #{arguments.join(", ")}")
          end
        end
      end
    end

    def self.start
      Commander.run(new.parse, ARGV)
    end
  end
end

Ven::CLI.start
