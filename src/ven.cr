require "fancyline"
require "commander"

require "inquirer/error"
require "inquirer/config"
require "inquirer/client"
require "inquirer/protocol"

require "./lib"

module Ven
  # Ven command line interface makes it easy to run Ven programs
  # interactively, from a file, or from a Ven distinct. It also
  # provides a set of helpful debugging & statistics middlewares,
  # plus a nice way to show Ven errors and program results.
  class CLI
    include Suite
    include Actions

    # The source code of the basis file. It is embedded into
    # the executable.
    #
    # The basis file contains the most primitive Ven code you
    # can find. It defines the defaults for protocol hooks &
    # useful action shorthands like `say`, `slurp`, etc.
    BASIS = {{read_file("#{__DIR__}/ven/library/basis.ven")}}

    # Consensus filename for the basis file.
    BASIS_NAME = "basis"

    # The path where the REPL history file can be found.
    HISTORY = ENV["VEN_HISTORY"]? || Path.home / ".ven_history"

    # Consensus filename of input from the REPL. If we see it
    # as the filename in an error, we assume it is reliable to
    # search in the interactive line buffer (`@lines`) for the
    # associated source code.
    INTERACTIVE = "interactive"

    # The regex matching a REPL command word. Command words
    # begin a REPL command (see `command`).
    COMMAND_WORD = /\\\w+/

    # The string `code` uses to separate line number from
    # the line itself.
    CODE_BARRIER = "| "

    # The indentation level before an excerpt of `code`.
    CODE_PREDENT = 2

    # Represents the CLI configuration.
    #
    # Every property in this class is mapped to the appropriate
    # command line flag, so you are free to use this as (more
    # verbose) help.
    class Config
      # Whether to quit after the program is executed.
      property quit = true
      # Consider the program executed when the execution
      # reaches this step.
      property final : Program::Step.class = Program::Step::Eval
      # Whether to print the result of the program after it
      # is executed.
      property result = false
      # The amount of octets of optimize passes.
      property optimize = 1
      # Whether to take overall (step) measurements, and
      # print them after the program is executed.
      property measure = false
      # The referent Inquirer client.
      property! inquirer : Inquirer::Client
      # Whether to apply this config to the children (exposed)
      # programs as well. Bloaty if you don't know what you're
      # doing.
      property propagate = false
      # Whether to record the timetable.
      property timetable = false
      # Whether to enable test mode.
      property test_mode = false
      # Whether to read all Ven input files using Inqurer's
      # `SourceFor` command. This affects:
      #
      #   - `ven path/to/file.ven`,
      #   - `ven distinct`,
      #   - all `expose`s.
      #
      # XXX: Whether this should be `true` by default, or `true`
      # when a connection with Inquirer is established, is still
      # undecided.
      property using_inquirer = false
    end

    # The Dis formatter implementation used in `show(chunk)`.
    class ShowChunkFormat < Dis::DefaultFormat
      @jumps = {} of VJump => Colorize::ColorRGB

      # Paints the super instruction pointer in dark gray,
      # or in a color from *@jumps*, if this IP is the target
      # of one of the jumps there.
      def on_ip(io, ctx)
        if kv = @jumps.find { |k, _| k.target == ctx.ip }
          _, rgb = kv
          # Colorize with the random colors picked by the
          # jump adder.
          color = "".colorize(rgb)
        else
          color = Colorize.with.dark_gray
        end

        color.surround(io) { super }
      end

      # Makes the super opcode bold.
      def on_opcode(io, ctx)
        Colorize.with.bold.surround(io) { super }
      end

      # Redirects to super unless current instruction argument
      # resolves to a `VJump`. If it does, makes a random RGB
      # color & puts it into *@jumps* under the corresponding
      # jump, colorizes the jump with that random color, and
      # appends it to *io*.
      def on_argument(io, ctx)
        return super unless ctx.instruction.argument.is_a?(Int32)
        return super unless jump = ctx.chunk.resolve(ctx.instruction).as?(VJump)

        # Make a random RGB color, and record it in the hash.
        #
        # Very unlikely, but it can exhaust/randomize its way
        # to the same color.
        color = @jumps[jump] ||= Colorize::ColorRGB.new(
          rand(UInt8),
          rand(UInt8),
          rand(UInt8),
        )

        "".colorize(color).surround(io) do
          io << jump
        end
      end
    end

    # The Dis formatter implementation used in `show(timetable)`.
    class ShowTimetableFormat < ShowChunkFormat
      # Initializes this formatter with the given chunk *statistic*.
      def initialize(@statistic : Machine::ChunkStatistic)
      end

      # Appends the relevant time/statistical data to the
      # super instruction argument.
      def on_argument(io, ctx)
        super

        # Get the instruction statistic for the current
        # instruction. Thankfully, the context has the
        # IP we can use.
        return unless for_ins = @statistic.instructions[ctx.ip]?

        amt = for_ins.amount
        dur = for_ins.duration

        amt_s =
          if amt < 100
            amt.colorize.green
          elsif amt < 1_000
            amt.colorize.yellow
          elsif amt < 10_000
            amt.colorize.light_red
          else
            amt.colorize.red
          end

        dur_s, unit = Utils.with_unit(dur)

        case unit
        when "ns"
          unit = unit.colorize.green
        when "us"
          unit = unit.colorize.yellow
        when "ms"
          unit = unit.colorize.light_red
        else
          unit = unit.colorize.red.bright
        end

        Colorize.with.dark_gray.surround(io) do
          io << " [N: " << amt_s << ", T: " << dur_s.colorize.white << unit

          # If this instruction was called more than once, print T/N
          # too (arithmetic mean time of instruction in the run).
          if amt > 1
            mean, mean_unit = Utils.with_unit(dur / amt)

            io << ", T/N: " << mean.colorize.white << mean_unit
          end

          io << "]"
        end
      end
    end

    # The line buffer (used by the REPL to show excerpts of
    # code in error messages).
    @lines = [] of String

    def initialize
      Colorize.on_tty_only!

      @hub = CxHub.new

      # Create the config object with all defaults. The
      # CLI machinery will fill it in.
      @config = Config.new

      # Extend with all builtin libraries. This might need some
      # control later on. Some libraries, `http`, for example,
      # should be `expose`d by the user, not auto-imported.
      {% for library in Extension.subclasses %}
        @hub.extend({{library}}.new)
      {% end %}

      @orchestra = Orchestra.new(@hub,
        ->pull(Distinct),
        ->read(String),
      )
    end

    # Sends a *command*, *argument* Request using the Inquirer
    # connection from the configuration object (`Config#inquirer`).
    #
    # If isolated, prints a warning and returns nil.
    #
    # Returns nil if generally unsuccessful. Otherwise, returns
    # Inquirer's `Inquirer::Protocol::Response::RType`.
    def inquire(command : Inquirer::Protocol::Command, argument : String)
      unless @config.inquirer.running?
        return warn("this instance of Ven is not connected to Inquirer")
      end

      request = Inquirer::Protocol::Request.new(command, argument)
      response = @config.inquirer.send(request)

      if response.status.err?
        {% if flag?(:release) %}
          return
        {% else %}
          return warn("inquire(#{command}, #{argument}): #{response.result}")
        {% end %}
      end

      response.result
    end

    # :ditto:
    def inquire(command : String, argument : String)
      inquire(Inquirer::Protocol::Command.parse(command), argument)
    end

    # Implements the pull function for the Orchestra.
    #
    # If isolated, prints a warning and returns nil. Otherwise,
    # makes a FilesFor request to Inquirer, and returns the
    # array of filenames (or nil).
    def pull(distinct : Distinct) : Array(String)?
      inquire("FilesFor", distinct.join('.')).as?(Array(String))
    end

    # Implements the read function for the Orchestra.
    #
    # If `--using-inquirer` flag (see `Config#using_inquirer`)
    # is true, sends a `SourceFor` to Inqurer, and returns the
    # resulting source (or nil).
    #
    # Otherwise, it is just a safety wrapper around `File.read`,
    # which returns nil if the file does not exist.
    def read(readable : String) : String?
      if @config.using_inquirer
        return inquire("SourceFor", readable).as?(String)
      end

      if File.file?(readable) && File.readable?(readable)
        File.read(readable)
      end
    end

    # Returns the *line*-th line in *filename*. **lineno
    # counts from 1 on.**
    #
    # If filename is `INTERACTIVE`, returns the line from
    # the interactive line buffer.
    def getline?(filename : String, lineno : Int32) : String?
      return @lines[lineno - 1]? if filename == INTERACTIVE

      if contents = read(filename)
        # This looks rather inefficient compared to reading
        # line-by-line, and stopping on the line requested,
        # but `read` compatibility is more important.
        contents.lines[lineno - 1]?.try &.strip
      end
    end

    # Prints a yellow warning message.
    def warn(comment : String) : Nil
      puts "[#{"warning".colorize.yellow}] #{comment}"
    end

    # Prints an error with the given *category* and *comment*.
    #
    # If `Config#quit` is set to true, quits with status 1.
    def err(category : String, comment : String) : Nil
      puts "[#{category.colorize.light_red}] #{comment}"

      exit(1) if @config.quit
    end

    # Stylizes a *line* of code. Syntax highlights *line*.
    # *lineno* is the line number, and *underline* may specify
    # the character range to underline.
    def code(line : String, lineno : Int32, underline : Range(Int32?, Int32?) = .., indent = 2)
      String.build do |io|
        io << " " * indent << lineno << CODE_BARRIER
        io << Utils.highlight(line, @hub.reader)

        if b = underline.begin
          padding = indent + {{CODE_BARRIER.size}} + lineno.to_s.size + b - 1

          # Compute the length (the amount of underline characters).
          #
          # If the end is undefined, default to 1.
          length = underline.end ? underline.end.not_nil! - b : 1

          # Pick the right symbol. There is no point in '-'ing
          # one character, it doesn't look good.
          symbol = length <= 1 ? "^" : ("-" * length)

          io << "\n" << " " * padding << symbol.colorize.green
        end
      end
    end

    # Prints the given traces. Uses `code` to stylize the
    # matching line of code, if any.
    #
    # **A newline is prepended before the traces.**
    def traces(traces : Traces, indent = 2)
      String.build do |io|
        traces.each do |trace|
          io << "\n"
          io << " " * indent << "in " << trace.desc.colorize.bold
          io << " (" << trace.file << ":" << trace.line << ")"
          if line = getline?(trace.file, trace.line)
            io << "\n" << code(line, trace.line, indent: indent + 2)
          end
        end
      end
    end

    # Dies of a `ReadError`. *lines* is a reference to an Array
    # of strings with the lines of the corresponding source code.
    def die(error e : ReadError)
      comment = String.build do |io|
        io << e.message << " (in " << e.file << ":" << e.line

        # If there is no begin_column, but is `.lexeme`, show
        # the lexeme. If there is no `.lexeme` too, close off.
        if b = e.begin_column
          io << ":" << b
        elsif lexeme = e.lexeme
          io << ", near " << lexeme
        end

        io << ")"

        # If there is a line to display, pass it to `code`,
        # which will do the job.
        if line = getline?(e.file, e.line)
          io << "\n" << code(line, e.line, b...e.end_column)
        end
      end

      err("read error", comment)
    end

    # Dies of a `CompileError` with traceback.
    def die(error e : CompileError)
      err("compile error", "#{e.message}#{traces(e.traces)}")
    end

    # Dies of a `RuntimeError` with traceback.
    def die(error e : RuntimeError)
      err("runtime error", "#{e.message}#{traces(e.traces)}")
    end

    # Dies of an `InternalError`.
    def die(error e : InternalError)
      err("internal error", e.message.not_nil!)
    end

    # Dies of an `ExposeError`.
    def die(error e : ExposeError)
      err("expose error", e.message || "bad expose")
    end

    # Dies of a generic (unknown) error.
    def die(error)
      err("error", error.to_s)
    end

    # Detrees, and consequently prints, the given *quotes*.
    #
    # Returns nothing.
    def show(quotes : Quotes)
      puts Detree.detree(quotes)
    end

    # Disassembles, and consequently prints, the given *chunks*.
    #
    # Returns nothing.
    def show(chunks : Chunks)
      chunks.each do |chunk|
        puts Dis.dis(chunk, ShowChunkFormat.new)
        puts
      end
    end

    # Formats, and consequently prints, the given *timetable*.
    #
    # Returns nothing.
    def show(timetable : Machine::Timetable)
      timetable.chunks do |statistic|
        fmt = ShowTimetableFormat.new(statistic)

        puts Dis.dis(statistic.subject, fmt)
        puts
      end
    end

    # Prints *value* if `Config#result` is set to true, and
    # *value* is not nil.
    #
    # Returns nothing.
    def show(value)
      puts value if @config.result && value
    end

    # Injects step measurement middleware to *program*, and
    # returns the hash of the measurements. Make sure to
    # wait until the program executes before reading from
    # this hash.
    def measure(program : Program) : Hash(String, Time::Span)
      measurements = {} of String => Time::Span

      {% for step in Program::Step::NAMES %}
         program.before_{{step.id}} do
           measurements[{{step}}] = Time.monotonic
         end

         program.after_{{step.id}} do
           measurements[{{step}}] = Time.monotonic - measurements[{{step}}]
         end
      {% end %}

      measurements
    end

    # Builds the master callback for Orchestra according to
    # the configuration of this CLI. `show`s everything that
    # is expected to be shown, including, if necessary, the
    # result of the program.
    def master(program : Program)
      timetable = Machine::Timetable.new

      program.before_compile do |compiler|
        compiler.ensure_tests = @config.test_mode
      end

      program.before_optimize do |optimizer|
        optimizer.passes = @config.optimize * 8
      end

      program.before_eval do |machine|
        if @config.timetable
          machine.measure = true
          machine.timetable = timetable
        end
      end

      # The measurement middleware should be the closest
      # to the program evaluation.
      measurements = @config.measure && measure(program)

      result = program.result(@config.final)

      show timetable

      if measurements.is_a?(Hash) && !measurements.empty?
        puts (
          String.build do |io|
            io << "Measurements for " << program.filename.colorize.underline << "\n"

            measurements.each do |step, span|
              duration, unit = Utils.with_unit(span)

              io << "[" << step.colorize.bold << "] "
              io << duration << unit << "\n"
            end
          end
        )
      end

      show result
    end

    # Builds the children callback for Orchestra according
    # to the configuration of this CLI.
    def children(program : Program)
      # Test mode propagates even with propagation disabled.
      program.before_compile do |compiler|
        compiler.ensure_tests = @config.test_mode
      end

      program.result(@config.final)
    end

    # Plays the given program, *respecting the propagate
    # flag from the configuration.*
    def play(program : Program | Distinct)
      @orchestra.play(program,
        ->master(Program),
        if @config.propagate
          ->master(Program)
        else
          ->children(Program)
        end
      )
    end

    # Evaluates the given *program*: injects the `master`, `children`
    # middlewares necessary to fulfil the configuration object, and
    # plays it in the orchestra.
    def eval(program : Program)
      if program.filename == INTERACTIVE
        # Capture the current line number. Don't subtract 1,
        # since we count from 1.
        lineno = @lines.size

        program.before_read do |reader|
          reader.lineno = lineno
        end
      end

      play(program)
    end

    # Makes a program from the given *source* and *filename*,
    # and `show`s the result of `eval`uating it.
    def run(filename : String, source : String)
      program = Program.new(source, filename, hub: @hub)

      eval(program)
    rescue e : VenError
      die(e)
    end

    # Processes a REPL command.
    def command(head : String, tail : String)
      die("REPL commands are temporarily disabled")
    end

    # Launches the read-eval-print loop.
    def repl
      fancy = Fancyline.new

      fancy.display.add do |ctx, line, yielder|
        if line.starts_with?(COMMAND_WORD)
          # Highlight the REPL instruction, given the line
          # starts with one.
          yielder.call ctx, line.sub(COMMAND_WORD) { $0.colorize.yellow }
        else
          yielder.call ctx, Utils.highlight(line, @hub.reader)
        end
      end

      # Load the REPL history.
      if File.file?(HISTORY) && File.readable?(HISTORY)
        File.open(HISTORY, "r") { |io| fancy.history.load(io) }
      end

      hint = "Hint:".colorize.blue
      puts <<-END.gsub(/\\\w+/) { |cmd| cmd.colorize.yellow }

        [Ven #{VERSION}]

        #{"Hit CTRL+D to exit.".colorize.bold}

        #{hint} Type \\help to see what REPL commands are available.
        \n
      END

      prompt = " #{"~>".colorize.dark_gray} "

      loop do
        rprompt = " [#{@lines.size + 1}]".colorize.dark_gray

        begin
          source = fancy.readline(prompt, rprompt.to_s).try(&.strip)
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

        fancy.grab_output do
          # Store the input in the line buffer.
          @lines.concat source.split('\n')

          run(INTERACTIVE, source)
        end
      end

      File.open(HISTORY, "w") do |io|
        fancy.history.save(io)
      end

      puts "Bye bye!"
      exit(0)
    end

    # Returns the Commander command line interface for Ven.
    def main
      Commander::Command.new do |cmd|
        cmd.use = "ven"
        cmd.long = Ven::VERSION

        # Unmapped flags are passed to the program.
        cmd.ignore_unmapped_flags = true

        cmd.flags.add do |flag|
          flag.name = "inquirer"
          flag.short = "-i"
          flag.long = "--inquirer"
          flag.default = 12879
          flag.description = "Set the referent Inquirer port."
        end

        cmd.flags.add do |flag|
          flag.name = "measure"
          flag.short = "-m"
          flag.long = "--measure"
          flag.default = false
          flag.description = "Measure, and consequently show, the time each step took."
        end

        cmd.flags.add do |flag|
          flag.name = "timetable"
          flag.short = "-M"
          flag.default = false
          flag.description = "Measure, and consequently show, the time each instruction took."
        end

        cmd.flags.add do |flag|
          flag.name = "final"
          flag.short = "-j"
          flag.long = "--just"
          flag.default = "eval"
          flag.description = "Can be: read, transform, optimize, compile, eval."
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
          flag.description = "The number of octets of optimization passes."
        end

        cmd.flags.add do |flag|
          flag.name = "test-mode"
          flag.short = "-t"
          flag.long = "--test"
          flag.default = false
          flag.description = "Disignore ensure tests."
        end

        cmd.flags.add do |flag|
          flag.name = "propagate"
          flag.long = "--propagate"
          flag.default = false
          flag.description = "(bloaty!) Propagate these flags to exposed programs"
        end

        cmd.flags.add do |flag|
          flag.name = "using-inquirer"
          flag.long = "--using-inquirer"
          flag.default = false
          flag.description = "Whether to read all input files using Inqurer"
        end

        # Generate flags for each `BaseAction` subclasses'
        # category. Automake the description.
        categories = {{BaseAction.subclasses}}.map(&.category).uniq.reject("screen")
        categories.each do |category|
          cmd.flags.add do |flag|
            flag.name = "with-#{category}"
            flag.long = "--with-#{category}"
            flag.default = false
            flag.description = "enable #{category} category actions"
          end
        end

        cmd.run do |options, arguments|
          # Enable the actions the user chose to enable. Each
          # action has a static property, `.enabled`, which we
          # set depending on the presence of the category flag.
          {% for action in BaseAction.subclasses %}
            %category = {{action}}.category
            {{action}}.enabled =
              # Screen category is always enabled.
              %category == "screen" \
                || options.bool["with-#{%category}"]
          {% end %}

          # Try to connect to Inquirer. The PULL Proc will use
          # this connection to communicate with Inquirer.
          #
          # Get `VEN_INQUIRER_HOST` from the environment, or
          # use the default 0.0.0.0. This is mostly useful
          # for Docker Compose / Docker.
          @config.inquirer = Inquirer::Client.new(
            begin
              config = Inquirer::Config.new
              config.port = options.int["inquirer"].as(Int32)
              config
            end,
            ENV["VEN_INQUIRER_HOST"]? || "0.0.0.0"
          )

          @config.measure = options.bool["measure"]
          @config.timetable = options.bool["timetable"]
          @config.result = options.bool["result"]
          @config.optimize = options.int["optimize"].as(Int32)
          @config.test_mode = options.bool["test-mode"]
          @config.propagate = options.bool["propagate"]
          @config.using_inquirer = options.bool["using-inquirer"]

          if step = Program::Step.parse?(final = options.string["final"])
            @config.final = step
          else
            die("no such step: #{final}")
          end

          # Load the basis file. Note how it does not respect
          # the propagate flag.
          @orchestra.play Program.new(BASIS, BASIS_NAME, hub: @hub)

          if arguments.empty?
            # If we are going to run the REPL, do not quit
            # after errors, and do print the result.
            @config.quit = false
            @config.result = true

            repl
          else
            file = arguments.first

            # Provide the unmapped flags/remaining arguments
            # to the orchestra. It's a bit risky, as some
            # user-defined flags may interfere with this CLI's.
            #
            # Also note that **all** programs of the orchestra
            # will have access to ARGS, including any side
            # library.
            @hub.machine["ARGS"] = Vec.from(arguments[1...], Str)

            if content = read(file)
              run File.expand_path(file), content
            elsif file =~ /^(\w[\.\w]*[^\.])$/
              play file.split('.')
            else
              die("no such file: '#{file}'")
            end
          end
        rescue e : VenError
          die(e)
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
