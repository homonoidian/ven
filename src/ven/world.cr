module Ven
  class World
    include Component

    getter reader, machine, context

    # Whether or not this World is verbose.
    setter verbose : Bool = false

    def initialize
      # Scraps are all '.ven' files this origin has.
      @scraps = [] of String
      @gathered = [] of Array(String)

      @reader = Reader.new
      @machine = Machine.new
      @context = Component::Context.new

      @reader.world = self
      @machine.world = self
    end

    def visit(quote)
      @machine.last = quote

      begin
        @machine.visit!(quote)
      rescue interrupt : NextInterrupt
        scope = interrupt.scope ? " #{interrupt.scope}" : ""

        @machine.die("world caught 'next#{scope}'")
      end
    end

    # Sets the origin of this world to *path*. Origin is the
    # root directory of the module. It must contain, and such
    # check is performed here, an **entry** file, which must
    # have the same name as the basename of *path* (e.g., for
    # origin `a/b/c/` entry is `c.ven`, i.e., `a/b/c/c.ven`).
    def origin!(path : Path)
      unless File.exists?(entry = path / "#{path.basename}.ven")
        raise WorldError.new("module origin has no entry: make sure '#{entry}' exists")
      end

      upscrap(path)

      feed "origin entry #{entry}", File.read(entry)
    end

    # Collects all '.ven' files in *path*, which should be
    # a directory (this is **not** checked).
    def scrap(path : Path)
      Dir["#{path}/**/*.ven"]
    end

    # Updates the scraps of this World by `scrap`ping *path*.
    def upscrap(path : Path)
      @scraps += scrap(path)
    end

    # Checks if the *scrap*'s first statement is a `distinct`
    # statement, then makes sure *pieces* starts with this
    # distinct's pieces, and evaluates the rest of the statements
    # within this world. Returns the status of the whole operation:
    # true if all went good and false otherwise.
    def expose!(pieces : Array(String), scrap : String)
      first = true
      distinct = false
      contents = File.read(scrap)

      # Fresh Readers are required for every scrap, as this
      # World's Reader is *in progress* of reading the entry.
      scrap_reader = Reader.new
      scrap_reader.world = self

      scrap_reader.read(scrap, contents) do |quote|
        if first && quote.is_a?(QDistinct)
          # (this is the first statement, this is distinct)
          if quote.pieces[0, pieces.size]? == pieces
            # (this distinct's pieces match *pieces*)
            first = false
            distinct = true

            if @verbose
              puts "[debug: Distinct *found* in '#{scrap}': it is" \
                   " #{quote.pieces}, while I searched for #{pieces}]",
                   "[debug: Now I know about: #{quote.pieces}]"
            end

            next @gathered << quote.pieces
          end
        elsif !first
          if distinct && quote.is_a?(QDistinct)
            # (there was a distinct and this is a distinct)
            raise WorldError.new(quote.tag,
              "duplicate 'distinct' statement in one file")
          elsif distinct
            # (there was distinct)
            next visit(quote).as(Model)
          end
        end

        return false
      end

      true
    end

    # Goes through the available `@scraps`, searching for ones
    # that `expose!` *pieces*. Returns whether or not one or more
    # of such scraps were found.
    def gather(pieces : Array(String))
      found = gathered?(pieces)

      if @verbose
        puts "[debug: Do I know about #{pieces}? #{found ? "yes" : "no"}]"
      end

      unless found
        @scraps.each do |scrap|
          if @verbose
            puts "[debug: I will try to find #{pieces} in '#{scrap}']"
          end

          if expose!(pieces, scrap)
            found = true

            # May have gathered the pieces of the module,
            # but not the module as a whole.
            unless gathered?(pieces)
              @gathered << pieces
            end
          end
        end
      end

      found
    end

    # Returns whether the *scrap* had already been gathered
    # (see `gather`).
    def gathered?(pieces : Array(String))
      @gathered.includes?(pieces)
    end

    # Loads given *extensions*, a bunch of Component::Extension
    # subclasses.
    def load(*extensions : Component::Extension.class)
      extensions.each do |extension|
        extension.new(@context).load
      end
    end

    # Reads and evaluates a String of *source* under the
    # filename *filename*.
    def feed(filename : String, source : String)
      @reader.read(filename, source) do |quote|
        visit(quote)
      end
    end
  end
end
