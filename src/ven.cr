require "fancyline"
require "option_parser"

require "./ven/**"

module Ven
  VERSION = "0.1.1-rev01"

  class CLI
    # The places the interpreter will visit to gather the modules
    # a script required. `BOOT` is a compile-time environment
    # variable containing the path to a boot module (the first
    # to load & one which defines the internals.)
    LOOKUP = [Dir.current, {{env("BOOT") || ""}}]

    def initialize
      @world = World.new

      @world.load(Library::Core)
      @world.load(Library::System)
    end

    # Prints the *message* and quits with exit status 0.
    def error(message : String)
      puts message

      exit(0)
    end

    # Prints the *message* of some *kind* and, if given true
    # *quit*, quits with exit status 1.
    def error(kind : String, message : String, quit = false)
      puts "#{kind.colorize(:light_red).bold}: #{message}"

      if quit
        exit(1)
      end
    end

    # Chooses the appropriate kind and message for *this*,
    # a Ven error, and `error`s them. If *quit* is true,
    # exits with status 1 afterwards.
    def error(this : Component::VenError, quit = true)
      message = this.message.not_nil!

      case this
      when Component::ReadError
        error("read error", "#{message} (in #{this.file}:#{this.line}, near '#{this.lexeme}')")
      when Component::RuntimeError
        error("runtime error", message)
      when Component::InternalError
        error("internal error", message)
      end

      if quit
        exit(1)
      end
    end

    # Reads and evaluates a script found at *path*. Handles
    # File::NotFoundError. On an error, exits with status 1.
    def script(path : String)
      path = Path[path].expand(home: true).to_s
      source = File.read(path)

      @world.feed(path, source)
    rescue exception : Component::VenError
      error(exception)
    rescue exception : File::NotFoundError
      error("command-line error", "file not found (or path invalid): #{path}", quit: true)
    end

    # Starts a new Read-Eval-Print loop.
    def repl
      fancy = Fancyline.new

      puts "Hit CTRL+D to exit, or Tab to autocomplete a symbol."

      loop do
        begin
          source = fancy.readline(" ~> ")
        rescue Fancyline::Interrupt
          next puts
        end

        if source.nil?
          error("Bye bye!")
        elsif source.empty? || source.starts_with?("#")
          next
        end

        begin
          puts @world.feed("<interactive>", source)
        rescue exception : Component::VenError
          error(exception, quit: false)
        end
      end
    end

    # Parses the command-line arguments and dispatches further
    # to `repl`, `script`, etc.
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

        parser.unknown_args do |args|
          case args.size
          when 0
            repl
          when 1
            script(args.first)
          else
            error(parser.to_s)
          end
        end
      end
    end
  end
end

Ven::CLI.new.run
