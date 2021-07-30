require "inquirer/error"
require "inquirer/config"
require "inquirer/client"
require "inquirer/protocol"

module Ven
  # `Orchestra` is the higher-level abstraction of the Ven
  # infrastructure. It handles the communication between several
  # `Program`s, between Ven and Inquirer, and between Ven and
  # Ven language server implementation.
  class Orchestra
    include Inquirer::Protocol

    # Returns the context hub of this orchestra.
    getter hub = Suite::CxHub.new
    # Returns Inquirer port number this orchestra is
    # connected to (unless `isolated`).
    getter port : Int32
    # Returns the chunk pool of this orchestra.
    getter pool = Suite::Chunks.new
    # Returns whether this orchestra is isolated from an
    # Inquirer server.
    getter isolated : Bool

    # The cache of `expose`s.
    @cache = Set(String).new

    # The Inquirer client of this Orchestra.
    @client : Inquirer::Client

    # An `Enquiry` with all defaults; we don't want to make
    # a new Enquiry every time we `expose`.
    @enquiry = Enquiry.new

    # Makes an Orchestra. *port* is the port on which the
    # desired Inquirer server is running.
    def initialize(@port = 12879)
      config = Inquirer::Config.new
      config.port = @port
      @client = Inquirer::Client.from(config)
      @isolated = !@client.running?

      # Automatically load `Extension`s.
      {% for library in Suite::Extension.all_subclasses %}
        @hub.extend({{library}}.new)
      {% end %}
    end

    # Returns an array of files required to expose the
    # given *distinct*.
    #
    # Raises `ExposeError` if failed.
    def files_for(distinct : Distinct)
      dotted = distinct.join('.')
      request = Request.new(Command::FilesFor, dotted)
      response = @client.send(request)

      unless files = response.result.as?(Array)
        raise Suite::ExposeError.new("could not expose '#{dotted}'")
      end

      files
    end

    # Yields files required to expose the given *distinct*.
    #
    # Raises `ExposeError` if failed.
    def files_for(distinct : Distinct)
      files_for(distinct).each do |filename|
        yield filename
      end
    end

    # Builds a `Program` from *source* and *filename*, recurses
    # on its exposes, and runs it if *run* is true, otherwise,
    # returns it.
    private def expose(filename : String, source : String, run = true)
      @cache << filename

      program = Program.new(source, filename, @hub, @enquiry)

      if @isolated && !program.exposes.empty?
        raise Suite::ExposeError.new(
          "you cannot use 'expose', as the referent Inquirer " \
          "server is not running")
      end

      exposes = program.exposes
      # Expose members of own distinct.
      exposes = [program.distinct.not_nil!] + exposes if program.distinct

      exposes.uniq.each do |expose|
        files_for(expose) do |dependency|
          unless dependency.in?(@cache)
            # Expose the dependency unless in cache.
            expose(dependency, File.read(dependency))
          end
        end
      rescue error : Suite::ExposeError
        # Re-raise unless it was trying to include itself,
        # but got out of recursion thanks to cache.
        raise error unless program.distinct == expose
      end

      run ? program.run(@pool) : program
    end

    # Runs the given *source* code, which can be found in
    # *file*, as a composer program.
    def from(source : String, filename = "unknown", @enquiry = Enquiry.new, run = true)
      expose(filename, source, run)
    end
  end
end
