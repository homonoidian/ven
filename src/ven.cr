require "fancyline"
require "option_parser"

require "./ven/**"

module Ven
  VERSION = "0.1.1-rev10"

  class CLI
    include Suite

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
        error("runtime error", message)
      when InternalError
        error("internal error", message)
      end

      if quit
        exit(1)
      end
    end

    def process(file : String, source : String)
      reader = Reader.new.reset
      compiler = Compiler.new(file)

      rt = Time.measure do
        reader.read(file, source) do |statement|
          compiler.visit(statement)
        end
      end

      m = Machine.new([compiler.chunk])

      mt = Time.measure do
        m.start
      end

      puts "READ & COMPILE :: #{rt.microseconds}qs"
      puts "EVAL :: #{mt.microseconds}qs"
    end

    def open(path : String)
      unless File.exists?(path)
        error("command-line error", "file not found: #{path}", quit: true)
      end

      process path, File.read(path)
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
        elsif source.empty? || source.starts_with?("#)")
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
