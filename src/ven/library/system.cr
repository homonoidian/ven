require "digest"

module Ven::Library
  # System
  class System < Suite::Extension
    SHA256 = OpenSSL::Digest::SHA256

    @files = Hash(BigInt, File).new

    # Adds the file at *path* to the `@files` registry. The
    # key is a SHA256 digest of *path*; it is returned, as
    # a `BigInteger`. The file is opened with mode *mode*.
    def register(path : String, mode : String) : BigInt
      id = SHA256.hexdigest(path).to_big_i(16)

      @files[id] = File.open(path, mode)

      id
    end

    # Ensures that *address* exists in `@files` and returns
    # the file it addresses.
    def existing(machine : Machine, address : Num)
      unless file = @files[address.value.numerator]?
        machine.die("no file with this address: #{address}")
      end

      file
    end

    # Registers the file at path *path* at an address, and
    # returns this address.
    fun! "open", path : Str, mode : Str do |machine|
      begin
        Num.new register(path.value, mode.value)
      rescue e : Exception
        machine.die(e.message.try(&.downcase) || "unknown failure")
      end
    end

    # Closes the file at address *address*.
    fun! "close", address : Num do |machine|
      begin
        MBool.new (existing(machine, address).close || true)
      rescue e : IO::Error
        machine.die(e.message.try(&.downcase) || "unknown failure")
      end
    end

    # Returns whether a file exists at *path*.
    fun! "exists?", path : Str do |machine|
      MBool.new File.exists?(path.value)
    end

    # Writes one character *char* into the file at *address*.
    fun! "put", address : Num, char : Str do |machine|
      unless (value = char.value).size == 1
        machine.die("expected one character, got: #{char}")
      end

      begin
        existing(machine, address).write(value.to_slice)
      rescue e : IO::Error
        machine.die(e.message.try(&.downcase) || "unknown failure")
      end

      MBool.new(true)
    end

    # Reads one character of the file at address *address*.
    # Returns the character as a `Str`, or `MBool` false if
    # there is nothing to get (e.g. EOF).
    fun! "get", address : Num do |machine|
      begin
        unless char = existing(machine, address).read_char
          return MBool.new(false)
        end
      rescue e : IO::Error
        machine.die(e.message.try(&.downcase) || "unknown failure")
      end

      Str.new(char.to_s)
    end

    def load
      under "sys" do
        defun("open")
        defun("close")
        defun("exists?")
        defun("put")
        defun("get")
      end
    end
  end
end
