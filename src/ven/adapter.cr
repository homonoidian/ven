require "./suite/model"

# A collection of methods that simplify working with Ven
# models from Crystal.
module Ven::Adapter
  extend self

  include Ven::Suite

  # Returns *value*.
  def to_model(value : Model)
    value
  end

  # Converts *value* to `MNumber`.
  def to_model(value : Number)
    Num.new(value.to_big_d)
  end

  # Converts *value* to `MBool`.
  def to_model(value : Bool)
    MBool.new(value)
  end

  # Converts *value* to `MString`.
  def to_model(value : String)
    Str.new(value)
  end

  # Converts *value* to `MRegex`.
  def to_model(value : Regex)
    MRegex.new(value)
  end

  # Converts *value* to `MFullRange`, or `MPartialRange`.
  def to_model(value : Range)
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
  end

  # Converts *value* to `MVector`. Performs `to_model` on the
  # items too.
  def to_model(value : Array)
    Vec.new(value.map { |item| to_model(item).as(Model) })
  end

  # Wraps *value* in `MNative` over the given type, *T*.
  def to_model(value : T) forall T
    MNative(T).new(value)
  end
end
