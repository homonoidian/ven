require "inquirer/error"
require "inquirer/config"
require "inquirer/client"
require "inquirer/protocol"

module Ven
  # Ven Orchestra is the communication layer between the Ven
  # interpreter infrastructure and the Inquirer infrastructure.
  #
  # It is the highest abstraction of those currently provided
  # by Ven.
  #
  # Simply speaking, it interprets `expose` and `distinct`
  # statements (although `distinct`s are also interpreted
  # by Inquirer, but in a way that is a bit different).
  #
  # A *composer program* is the program that stands in place
  # of `X` in the following question:
  #
  # > What, and in what order, should I run before `X` so as
  # > to get `X` up and running.
  #
  # Their order, as well as files themselves, are managed
  # entirely by Inquirer.
  #
  # Basic usage:
  # ```
  # orchestra = Ven::Orchestra.new
  #
  # puts orchestra.from("1 + 1") # 2
  # ```
  class Orchestra
    include Inquirer::Protocol

    @hub   = Suite::Context::Hub.new
    @pool  = Suite::Chunks.new
    @cache = Set(String).new

    @client : Inquirer::Client

    # Makes an Orchestra for an Inquirer server running at
    # the given *port*.
    def initialize(port = 3000)
      @client = client_from(port)
      @isolated = !@client.running?
    end

    # Makes a client given the *port* of an Inquirer server
    # it will try to connect to.
    private def client_from(port : Int32)
      config = Inquirer::Config.new
      config.port = port
      Inquirer::Client.from(config)
    end

    # Asks the Inquirer server which files are required to
    # build the given *distinct*.
    #
    # Returns an array of filepaths (empty if failed).
    private def files_for?(distinct : Distinct)
      request = Request.new Command::FilesFor, distinct.join('.')
      response = @client.send(request)
      response.result.as?(Array) || [] of String
    end

    # Asks the Inquirer server which files are required to
    # build the given *distinct*.
    #
    # Returns an array of filepaths.
    #
    # Raises `ExposeError` if failed.
    private def files_for(distinct : Distinct)
      files = files_for?(distinct)

      if files.empty?
        raise Suite::ExposeError.new("could not expose '#{distinct.join('.')}'")
      end

      files
    end

    # Exposes the program found at *filepath*, and containing
    # the given *source*.
    private def expose(filepath : String, source : String)
      program = Program.new(source, filepath, hub: @hub)

      if @isolated && !program.exposes.empty?
        raise Suite::ExposeError.new(
          "you cannot use 'expose', as the Inquirer server " \
          "specified is not running")
      elsif !@isolated
        if distinct = program.distinct
          # foo.ven (composer):
          #
          # ```ven
          #   distinct foo.bar;
          #
          #   # expose foo.bar <<<------ done here, automatically
          #
          #   ensure add(1, 2) is 3;
          # ```
          #
          # bar.ven:
          #
          # ```ven
          #   distinct foo.bar;
          #
          #   # expose foo.bar <<<------ done here, automatically
          #
          #   fun add(a, b) = a + b;
          # ```
          files_for?(distinct).each do |umbrelloid|
            expose(umbrelloid) unless umbrelloid.in?(@cache)
          end
        end

        program.exposes.uniq.each do |expose|
          files_for(expose).each do |dependency|
            expose(dependency) unless dependency.in?(@cache)
          end
        end
      end

      program.run(@pool)
    end

    # Exposes the program found at *filepath*.
    private def expose(filepath : String)
      return if filepath.in?(@cache)

      # WARNING: do not remove this and the guard clause, as
      # doing so will provoke infinite expose.
      @cache << filepath

      expose(filepath, File.read filepath)
    end

    # Runs the given *source* code, which can be found in *file*,
    # as a composer program.
    def from(source : String, file = "composer")
      # WARNING: do not remove this, as doing so will provoke
      # infinite expose (in some cases).
      @cache << file

      expose(file, source)
    end
  end
end
