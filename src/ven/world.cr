module Ven
  # `World` manages communication & cooperation between the
  # different parts of Ven. It is also used as an inter-file
  # medium.
  class World
    include Suite

    getter reader, machine, context

    # Whether or not this World is verbose.
    setter verbose : Bool = false

    # An umbrella Ven module.
    private alias Module = { loaded: Bool, distincts: Array(Reader) }

    def initialize(boot : Path)
      # The paths in which we will search for '.ven' files.
      @lookup = [boot]

      # Module registry (the modules that we have found).
      @modules = {} of Array(String) => Module

      @reader = Reader.new
      @machine = Machine.new
      @context = Suite::Context.new

      @reader.world = self
      @machine.world = self
    end

    # Dies of `WorldError` with *message*.
    def die(message : String)
      raise WorldError.new(message)
    end

    # Adds *directory* to the lookup paths if there isn't
    # an identical path already.
    def <<(directory : Path)
      @lookup << directory unless @lookup.includes?(directory)
    end

    # Gathers all '.ven' files in the lookup directories and
    # registers each in `@modules`, under their appropriate
    # 'distinct' paths. *except* can be used to ignore a
    # specific '.ven' file.
    def gather(ignore : String? = nil)
      @lookup.each do |path|
        unless File.directory?(path)
          die("this lookup path is not a directory: #{path}")
        end

        puts "<gather in '#{path}'>" if @verbose

        # Get all '.ven' files in *path*. Try to search for
        # a 'distinct' in each one, and, if found, create
        # (or update) the corresponding entry in *@modules*.
        Dir["#{path}/**/*.ven"].each do |file|
          next if file == ignore

          contents = File.read(file)

          f_reader = Reader.new
          f_reader.world = self

          f_reader.read(file, contents) do |quote|
            break unless quote.is_a?(QDistinct)

            break @modules.has_key?(quote.pieces) \
              ? (@modules[quote.pieces][:distincts] << f_reader)
              : (@modules[quote.pieces] = { loaded: false, distincts: [f_reader] })
          end
        end
      end

      if @verbose
        @modules.each do |distinct, mod|
          puts "-> distinct #{distinct.join(".")}:"

          mod[:distincts].each do |f_reader|
            puts " |-> #{f_reader}"
          end
        end
      end
    end

    # Makes a list of candidate modules matching *distinct*
    # and evaluates these candidate modules in the context of
    # this world. Returns false if found no candidate modules.
    def expose(distinct : Array(String)) : Bool
      # Choose the modules whose names are equal to *distinct*
      # or start with *distinct*.
      candidates = @modules.select do |k|
        k[0, distinct.size]? == distinct
      end

      if candidates.empty?
        return false
      end

      candidates.each do |name, module_|
        # Make sure that we didn't evaluate this module already.
        unless module_.[:loaded]
          @modules[name] = { loaded: true, distincts: [] of Reader }

          module_[:distincts].each do |f_reader|
            puts "<expose(): visit using '#{f_reader}'>" if @verbose

            # Can't use Reader.new.read since it will reset, but
            # it's actually just a wrapper around `.module`.
            f_reader.module do |quote|
              visit(quote)
            end
          end
        end
      end

      true
    end

    # Returns the origin for the *directory*. Dies if this
    # origin does not exist.
    # Origin is a Ven script that has the same name as the
    # *directory*. For example, for the *directory* `a/b/c`
    # the origin will be `a/b/c/c.ven`.
    def origin(directory : Path)
      unless File.exists?(origin = directory / "#{directory.basename}.ven")
        die("origin file not found in '#{directory}': make sure '#{origin}' exists")
      end

      origin
    end

    # Visits a quote in the context of this world. Dies on any
    # interrupt (e.g. `NextInterrupt`) that was not captured.
    def visit(quote : Quote)
      @machine.last = quote

      begin
        @machine.visit!(quote)
      rescue interrupt : NextInterrupt
        @machine.die("#{interrupt} caught by the world")
      end
    end

    # Loads given *extensions* into the context of this world.
    def load(*extensions : Suite::Extension.class)
      extensions.each do |extension|
        extension.new(@context).load
      end
    end

    # Reads and evaluates *source* under the filename *filename*.
    def feed(filename : String, source : String)
      @reader.read(filename, source) do |quote|
        visit(quote)
      end
    end
  end
end
