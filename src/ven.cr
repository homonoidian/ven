require "fancyline"
require "commander"

require "./ven/**"

module Ven
  VERSION = "0.1.1-rev11"

  class CLI
    include Suite

    # All files & REPL inputs go to and through this Master.
    @master = Master.new

    # Flags and options important to this CLI.
    @quit = true
    @result = false
    @isolate = true

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
      err("expose error", "#{e.message} #{@isolate ? "(you are isolated)" : ""}")
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

      unless @isolate
        @master.gather
      end

      run file, File.read(file)
    end

    # Highlights a *snippet* of Ven code.
    private def highlight(snippet)
      state = :default

      snippet.split(/(?<!\-)\b(?!\-)/).flat_map do |word|
        if word[0]?.try(&.alphanumeric?)
          word
        else
          word.chars.map(&.to_s)
        end
      end.map do |word|
        case state
        when :string
          state = :default if word.ends_with?('"')
          next word.colorize.yellow
        when :pattern
          state = :default if word.ends_with?('`')
          next word.colorize.yellow
        end

        case word
        when /^"/
          state = :string
          word.colorize.yellow
        when /^`/
          state = :pattern
          word.colorize.yellow
        when /^#{Ven.regex_for(:NUMBER)}$/
          word.colorize.magenta
        when .in?(Reader::KEYWORDS)
          word.colorize.blue
        else
          word.colorize.bold.toggle(Input.context[word]?)
        end
      end.join
    end

    # Launches the read-eval-print loop.
    def repl
      fancy = Fancyline.new

      fancy.display.add do |ctx, line, yielder|
        yielder.call ctx, highlight(line)
      end

      puts "[Ven #{VERSION}]",
           "Hit CTRL+D to exit."

      unless @isolate
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
          flag.name = "result"
          flag.short = "-r"
          flag.default = false
          flag.description = "Display result of the program."
        end

        cmd.flags.add do |flag|
          flag.name = "disassemble"
          flag.short = "-d"
          flag.default = false
          flag.description = "Display pre-opt & post-opt bytecode."
        end

        cmd.flags.add do |flag|
          flag.name = "measure"
          flag.short = "-m"
          flag.default = false
          flag.description = "Display instruction timetable."
        end

        cmd.flags.add do |flag|
          flag.name = "isolate"
          flag.short = "-i"
          flag.default = false
          flag.description = "Run in isolation."
        end

        cmd.flags.add do |flag|
          flag.name = "verbose"
          flag.short = "-v"
          flag.default = 1
          flag.description = "Set verbosity level (0, 1, 2)."
        end

        cmd.flags.add do |flag|
          flag.name = "optimize"
          flag.short = "-O"
          flag.default = 1
          flag.description = "Set optimization level."
        end

        cmd.flags.add do |flag|
          flag.name = "inspect"
          flag.short = "-s"
          flag.default = false
          flag.description = "Enable step-by-step inspection."
        end

        cmd.flags.add do |flag|
          flag.name = "tree"
          flag.short = "-t"
          flag.default = false
          flag.description = "Display quote tree."
        end

        cmd.flags.add do |flag|
          flag.name = "tree-only"
          flag.short = "-T"
          flag.default = false
          flag.description = "Only read and display quote tree"
        end

        cmd.run do |options, arguments|
          @result = options.bool["result"]
          @isolate = options.bool["isolate"]

          @master.tree = options.bool["tree"]
          @master.passes = options.int["optimize"].as(Int32) * 8
          @master.inspect = options.bool["inspect"]
          @master.measure = options.bool["measure"]
          @master.tree_only = options.bool["tree-only"]
          @master.verbosity = options.int["verbose"].as(Int32)
          @master.disassemble = options.bool["disassemble"]

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
