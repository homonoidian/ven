require "./suite/model"

# A collection of methods that simplify working with Ven
# models from Crystal.
module Ven::Adapter
  extend self

  include Ven::Suite

  # Converts *value* to Ven model (see `Model`). Wraps in
  # `MNative` unless there is a corresponding Ven model.
  def to_model(value : T) forall T
    case value
    when Model
      value
    when Number
      Num.new(value.to_big_d)
    when Bool
      MBool.new(value)
    when String
      Str.new(value)
    when Regex
      MRegex.new(value)
    when Range
      b = value.begin
      e = value.end

      if e && value.excludes_end?
        # Exclusive range is the same as inclusive
        # range, but minus one from the end:
        #   ~> 1...200
        #   == 1..199
        # Ven's ranges are always inclusive.
        e -= 1
      end

      if b && e
        return MFullRange.new(Num.new(b), Num.new(e))
      end

      MPartialRange.new(
        b.try { |value| Num.new(value) },
        e.try { |value| Num.new(value) }
      )
    when Array
      Vec.new(value.map { |item| to_model(item).as(Model) })
    else
      MNative(T).new(value)
    end
  end
end
