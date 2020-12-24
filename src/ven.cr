require "fancyline"
require "option_parser"

require "./ven/*"
require "./ven/library/*"

module Ven
  VERSION = "0.1.0"

  module CLI
    extend self

    # Format and print an error (without exiting)
    def error(kind : String, explanation : String)
      puts "#{kind.colorize(:light_red).bold}: #{explanation}"
    end

    # Handle a VenError: print it and exit with status 1
    # (if `quit` is true)
    def error?(e : Component::VenError, quit = true)
      message = e.message.not_nil!

      case e
      when Component::ParseError
        error("parse error", "#{message} (in #{e.file}:#{e.line}, near '#{e.char}')")
      when Component::RuntimeError
        error("runtime error", message)
      when Component::InternalError
        error("internal error", message)
      end

      if quit
        exit(1)
      end
    end

    # Print the `message` and exit with status 0
    def quit(message : String)
      puts message
      exit(0)
    end

    # Create a Ven::Manager and initialize all builtin libraries
    def manager?(file : String)
      manager = Manager.new(file)

      manager.load(
        Library::Core,
        Library::System
      )

      manager
    end

    # Read and execute source from `path`. Exit on VenError.
    # Handle File::NotFoundError (for file not found / invalid path)
    def file(path : String)
      path = Path[path].expand(home: true).to_s
      source = File.read(path)
      manager = manager?(path)

      manager.feed(source)
    rescue e : Component::VenError
      error?(e)
    rescue e : File::NotFoundError
      error("command-line error", "file not found (or path invalid): #{path}")
    end

    # Prepare for and start a REPL
    def repl
      manager = manager?("<interactive>")

      fancy = Fancyline.new

      # Autocomplete symbols
      fancy.autocomplete.add do |ctx, range, word, yielder|
        completions = yielder.call(ctx, range, word)

        line = ctx.editor.line
        scope = manager.context.scope

        if line =~ /#{Ven.regex_for(:SYMBOL)}\-?$/
          range = (ctx.editor.line.size - $0.size)..-1

          scope.select(&.includes?($0)).each do |n, v|
            completions << Fancyline::Completion.new(range, n, "#{n} (#{v})")
          end
        end

        completions
      end

      puts "Hit CTRL+D to exit, or Tab to autocomplete a symbol."

      loop do
        begin
          source = fancy.readline(" ~> ")
        rescue Fancyline::Interrupt
          next puts
        end

        if source.nil?
          quit("Bye bye!")
        elsif source.empty? || source.starts_with?("#")
          next
        end

        begin
          puts manager.feed(source)
        rescue e : Component::VenError
          error?(e, quit: false)
        end
      end
    end

    # Parse the command-line arguments and dispatch.
    # The entry point to binary Ven
    def run
      OptionParser.parse do |parser|
        parser.banner = "Usage: #{PROGRAM_NAME} [options] [path/to/script.ven]"

        parser.separator("\nOptions and arguments:")

        parser.on "-v", "--version", "Show version and quit" do
          quit(VERSION)
        end

        parser.on "-h", "--help", "Show this message and quit" do
          quit(parser.to_s)
        end

        parser.invalid_option do |option|
          error("command-line error", "'#{option}' is not a valid option")
        end

        parser.unknown_args do |args|
          case args.size
          when 0
            repl
          when 1
            file(args.first)
          else
            error("command-line error", "unrecognized argument(s): #{args.join(", ")}")
          end
        end
      end
    end
  end
end

Ven::CLI.run
