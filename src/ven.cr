require "fancyline"
require "option_parser"

require "./ven/**"

module Ven
  VERSION = "0.1.1-rev01"

  class CLI
    # `BOOT` is a compile-time environment variable containing
    # the path to a boot module (the first to load & one which
    # defines the internals.) Indeed, it is a directory that
    # functions in the same way as origin modules do.
    BOOT = {{env("BOOT") || raise "unable to get 'BOOT'"}}

    def initialize
      @world = World.new

      @world.load(Library::Core)
      @world.load(Library::System)

      if @world.upscrap(Path[BOOT]).empty?
        raise "BOOT ('#{BOOT}') does not contain any Ven files"
      end
    end

    # Prints the *message* and quits with exit status 0.
    def error(message : String)
      puts message

      exit(0)
    end

    # Prints the *message* of some *kind* and, if given true
    # *quit*, quits with exit status 1.
    def error(kind : String, message : String, quit = false)
      kind = "(#{kind})"

      puts "#{kind.colorize(:light_red).bold} #{message}"

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
      when Component::WorldError
        error("world error", "#{message} (in #{this.file}:#{this.line})")
      end

      if quit
        exit(1)
      end
    end

    # Evaluates *source* with filename *filename*.
    def eval(filename : String, source : String)
      @world.feed(filename, source)
    end

    def open(path : String)
      this = Path[path].normalize.expand(home: true)

      if File.directory?(this)
        @world.origin!(this)
      elsif File.file?(this)
        eval this.to_s, File.read(this)
      else
        error("command-line error", "invalid option, file or directory: #{path}", quit: true)
      end
    rescue exception : Component::VenError
      error(exception)
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
          puts eval("<interactive>", source)
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
