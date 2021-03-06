require "fancyline"
require "option_parser"

require "./ven/**"

module Ven
  VERSION = "0.1.1-rev04"

  class CLI
    include Suite

    # `BOOT` is a compile-time environment variable containing
    # the path to a boot module (the first to load & one which
    # defines the internals.) Indeed, it is a directory that
    # functions in the same way as origin modules do.
    BOOT = Path[{{env("BOOT") || raise "unable to get 'BOOT'"}}]

    def initialize
      @world = World.new(BOOT)

      @world.load(Library::Core)
      @world.load(Library::System)
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
      when RuntimeError
        error("runtime error", "#{message}\n#{format_traces(this.trace)}")
      when InternalError
        error("internal error", message)
      when WorldError
        error("world error", message)
      end

      if quit
        exit(1)
      end
    end

    # Returns a string of properly formatted *traces*.
    # *root_spaces* is the number of spaces before each trace;
    # *code_spaces* is the number of spaces before each source
    # code excerpt.
    def format_traces(traces : Traces, root_spaces = 2, code_spaces = 4)
      result =
        traces.map do |trace|
          file = trace.tag.file
          line = trace.tag.line

          if File.exists?(file)
            lines = File.read_lines(file)
            erring = lines[line - 1].lstrip(" ")
            excerpt = "\n#{" " * code_spaces}#{line}| #{erring}"
          end

          "#{" " * root_spaces}in #{trace}#{excerpt}"
        end

      result.join("\n")
    end

    # Evaluates *source* under the filename *filename*.
    def eval(filename : String, source : String)
      @world.feed(filename, source)
    end

    # Does the necessary negotiations with the world and runs
    # the script/module *path*.
    def open(path : String)
      path = Path[path].normalize.expand(home: true)

      if File.directory?(path)
        @world << path
        path = @world.origin(path)
      elsif File.file?(path)
        @world << path.parent
      else
        error("command-line error", "invalid option, file or directory: #{path}", quit: true)
      end

      # Now, gather all '.ven' files we know about except
      # ourselves.
      @world.gather(ignore: path.to_s)

      eval path.to_s, File.read(path)
    rescue exception : VenError
      error(exception)
    end

    # Starts a new read-eval-print loop.
    def repl
      fancy = Fancyline.new

      puts "[Ven #{VERSION}]",
           "Hit CTRL+D to exit."

      # First, gather all '.ven' files we know about.
      @world.gather

      loop do
        begin
          source = fancy.readline(" ~> ")
        rescue Fancyline::Interrupt
          next puts
        end

        if source.nil?
          error("Bye bye!")
        elsif source.empty? || source.starts_with?("#)")
          next
        end

        begin
          puts eval("<interactive>", source)
        rescue exception : VenError
          error(exception, quit: false)
        end
      end
    end

    # Parses the command-line arguments and dispatches further
    # to `repl`, `open`, etc.
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

        parser.on "--verbose-world", "Make world verbose (debug)" do
          @world.verbose = true
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
