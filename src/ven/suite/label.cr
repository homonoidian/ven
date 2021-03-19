module Ven::Suite
  # A new, unique label.
  class Label
    def to_s(io)
      io << "label " << hash
    end
  end
end
