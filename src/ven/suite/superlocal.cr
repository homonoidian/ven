module Ven::Suite
  # A controller for a superlocal value, or a stack of
  # superlocal values.
  struct Superlocal(T)
    @values = [nil] of T?

    def initialize
    end

    protected def initialize(@values)
    end

    # Returns whether this superlocal's value is hole.
    def hole?
      @values.last.nil?
    end

    # Fills this superlocal with *value*.
    def fill(value : T)
      @values << value
    end

    # Takes the current superlocal value. Returns nil if the
    # current superlocal value is a hole.
    def take? : T?
      @values.pop unless hole?
    end

    # Taps the current superlocal value. Returns nil if the
    # current superlocal value is a hole.
    def tap? : T?
      @values.last
    end

    # Concatenates the values of *other* to the values of
    # this superlocal.
    def merge!(other : Superlocal(T))
      # The first value in values is always nil, we don't
      # want a rogue nil.
      merge!(other.@values[1..])
    end

    # Concatenates *others* to the values of this superlocal.
    def merge!(others : Array(T?))
      @values.concat(others)
    end

    def to_s(io)
      io << "Superlocal(" << @values.join(", ") << ")"
    end

    # Creates a shallow copy of this superlocal.
    #
    # **Does not** dup the superlocal values recursively. Instead,
    # it `dup`s the values array.
    def dup
      Superlocal(T).new(@values.dup)
    end

    # Alias to `dup`.
    def clone
      dup
    end
  end
end
