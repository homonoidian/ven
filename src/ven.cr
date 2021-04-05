require "fancyline"
require "option_parser"

require "./ven/**"

module Ven
  VERSION = "0.1.1-rev10"

  class CLI
    include Suite

    @quiet = 0
    @debug = false
    @passes = 8
    @timetable = false

    def initialize
      @master = Master.new
    end

    # Prints a *message* and quits with exit status 0.
    def error(message : String)
      puts message

      exit(0)
    end

    # Prints a *message* of some *kind* and, if given true
    # *quit*, quits with exit status 1.
    def error(kind : String, message : String, quit = false)
      kind = "[#{kind}]"

      puts "#{kind.colorize(:light_red).bold} #{message}"

      if quit
        exit(1)
      end
    end

    # Chooses the appropriate kind and message for *this*,
    # a Ven error, and `error`s. If *quit* is true, exits
    # with status 1 afterwards.
    def error(this : VenError, quit = true)
      message = this.message.not_nil!

      case this
      when ReadError
        error("read error", "#{message} (in #{this.file}:#{this.line}, near '#{this.lexeme}')")
      when CompileError
        error("compile-time error", "#{message}\n#{trace(this.traces)}")
      when RuntimeError
        error("runtime error", "#{message}\n#{trace(this.traces)}")
      when InternalError
        error("internal error", message)
      end

      if quit
        exit(1)
      end
    end

    # Formats an Array of `Trace`s.
    def trace(traces : Traces) : String
      traces.join("\n")
    end

    def process(file : String, source : String)
      puts @master.load(file, source)
    end

    def open(path : String)
      unless File.exists?(path)
        error("command-line error", "file not found: #{path}", quit: true)
      end

      begin
        process path, File.read(path)
      rescue e : VenError
        error(e)
      end
    end

    # Starts a new read-eval-print loop.
    def repl
      fancy = Fancyline.new

      puts "[Ven #{VERSION}]",
           "Hit CTRL+D to exit."

      loop do
        begin
          source = fancy.readline(" ~> ")
        rescue Fancyline::Interrupt
          next puts
        end

        if source.nil?
          error("Bye bye!")
        elsif source.empty? || source.starts_with?("# ")
          next
        end

        begin
          process("<interactive>", source)
        rescue exception : VenError
          error(exception, quit: false)
        end
      end
    end

    # Parses the command-line arguments and appropriately
    # passes control to the other methods.
    def run
      OptionParser.parse do |parser|
        parser.banner = "Usage: #{PROGRAM_NAME} [options] [path/to/script.ven]"

        parser.separator("\nOptions and arguments:")

        parser.on "-v", "--version", "Print version number and exit" do
          error(VERSION)
        end

        parser.on "-h", "--help", "Print this message and exit" do
          error(parser.to_s)
        end

        parser.on "-q", "(quietness) Print only the result" do
          @quiet = 1
        end

        parser.on "-Q", "(quietness) Be absolutely quiet" do
          @quiet = 2
        end

        parser.on "-t", "Print timetable (instr.-s time) after eval" do
          @timetable = true
        end

        parser.on "-d", "--debug", "Enable step-by-step mode" do
          @debug = true
        end

        parser.on "-O level", "--optimize level", "Set optimization level" do |level|
          @passes = 8 * level.to_i
        end

        parser.unknown_args do |args|
          case args.size
          when 0
            repl
          when 1
            open(args.first)
          else
            error(parser.to_s)
          end
        end
      end
    end
  end
end

Ven::CLI.new.run
