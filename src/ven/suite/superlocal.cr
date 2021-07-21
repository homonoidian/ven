module Ven::Suite
  # A controller for a superlocal value, or a stack of
  # superlocal values.
  struct Superlocal
    @values = [nil] of Model?

    # Returns whether this superlocal's value is hole.
    def hole?
      @values.last.nil?
    end

    # Fills this superlocal with *value*.
    def fill(value : Model)
      @values << value
    end

    # Takes the current superlocal value. Returns nil if the
    # current superlocal value is a hole.
    def take?
      @values.pop unless hole?
    end

    # Taps the current superlocal value. Returns nil if the
    # current superlocal value is a hole.
    def tap?
      @values.last unless hole?
    end

    def to_s(io)
      io << "Superlocal(" << @values.join(", ") << ")"
    end
  end
end
