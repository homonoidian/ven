# This module contains the implementations of Ven unary
# operators for readtime.
module Ven::Suite::Readtime::Unary
  extend self

  # Returns *operand*.
  def to_num(operand : QNumber) : QNumber
    operand
  end

  # Parses a number from *operand*, or dies.
  def to_num(operand : QString) : QNumber?
    QNumber.new(operand.tag, operand.value.to_big_d)
  end

  # Returns the length of *operand*.
  def to_num(operand : QVector) : QNumber
    QNumber.new(operand.tag, operand.items.size.to_big_d)
  end

  # Returns 1.
  def to_num(operand : QTrue) : QNumber
    QNumber.new(operand.tag, 1.to_big_d)
  end

  # Returns 0.
  def to_num(operand : QFalse) : QNumber
    QNumber.new(operand.tag, 0.to_big_d)
  end

  # Fallback: returns nil.
  def to_num(operand) : Nil
  end

  # Same as `to_num`, but negates the resulting number.
  def to_neg(operand) : QNumber?
    to_num(operand).try do |number|
      QNumber.new(number.tag, -number.value)
    end
  end

  # Returns *operand*.
  def to_str(operand : QString) : QString
    operand
  end

  # Detrees (see `Detree`) *operand*.
  def to_str(operand) : QString
    QString.new(operand.tag, Detree.detree(operand))
  end

  # Returns *operand*.
  def to_vec(operand : QVector) : QVector
    operand
  end

  # Surrounds *operand* with a vector.
  def to_vec(operand) : QVector
    QVector.new(operand.tag, [operand], filter: nil)
  end

  # Returns the length of string *operand*.
  def to_len(operand : QString) : QNumber
    QNumber.new(operand.tag, operand.value.size.to_big_d)
  end

  # Returns the length of vector *operand*.
  def to_len(operand : QVector) : QNumber
    QNumber.new(operand.tag, operand.items.size.to_big_d)
  end

  # Returns 1.
  def to_len(operand) : QNumber
    QNumber.new(operand.tag, 1.to_big_d)
  end

  # Returns true.
  def to_inv(operand : QFalse) : QTrue
    QTrue.new(operand.tag)
  end

  # Returns false.
  def to_inv(operand) : QFalse
    QFalse.new(operand.tag)
  end

  # Applies unary *operator* to *operand*, and returns the
  # result. Returns nil if the operation failed.
  def unary(operator : String, operand : Quote) : MaybeQuote
    case operator
    when "+"   then to_num(operand)
    when "-"   then to_neg(operand)
    when "~"   then to_str(operand)
    when "#"   then to_len(operand)
    when "&"   then to_vec(operand)
    when "not" then to_inv(operand)
    end
  end
end
