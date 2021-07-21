module Ven::Suite
  # A controller for a superlocal value, or a stack of
  # superlocal values.
  struct Superlocal(T)
    @values = [nil] of T?

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
      @values.last unless hole?
    end

    def to_s(io)
      io << "Superlocal(" << @values.join(", ") << ")"
    end
  end
end
