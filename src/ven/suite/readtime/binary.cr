# This module contains the implementations of Ven binary
# operators for readtime.
module Ven::Suite::Readtime::Binary
  extend self

  # Conjoins (i.e., joins with 'and') *left* and *right*.
  def conj(left : Quote, right : Quote) : Quote
    left.false? ? left : right
  end

  # Disjoins (i.e., joins with 'or') *left* and *right*.
  def disj(left, right) : Quote
    left.false? ? right : left
  end

  # Returns whether the given two quotes, *left* and *right*,
  # are equal, by serializing them into JSON and comparing
  # the resulting strings. Returns *left* if they are equal,
  # and `QFalse` if they aren't.
  def is?(left : Quote, right : Quote) : Quote
    return QFalse.new(left.tag) unless left.class == right.class
    return QFalse.new(left.tag) unless left.to_json == right.to_json

    left
  end

  # Returns *left* if *left*'s value is equal to *right*'s,
  # otherwise `QFalse`.
  def is?(left : QNumber, right : QNumber) : QNumber | QFalse
    left.value == right.value ? left : QFalse.new(left.tag)
  end

  # :ditto:
  def is?(left : QString, right : QString) : QString | QFalse
    left.value == right.value ? left : QFalse.new(left.tag)
  end

  # Returns *left* if each item of *left* `is?` the corresponding
  # item of *right*, otherwise `QFalse`.
  def is?(left : QVector, right : QVector) : QVector | QFalse
    l = left.items
    r = right.items

    # The two vectors are not equal if their sizes differ.
    return QFalse.new(left.tag) unless l.size == r.size

    # Recurse on the pairs.
    l.zip(r) do |my, its|
      return QFalse.new(left.tag) if is?(my, its).false?
    end

    left
  end

  # Returns *left*.
  def is?(left : QTrue, right : QTrue) : QTrue
    left
  end

  # Returns `QTrue`.
  def is?(left : QFalse, right : QFalse) : QTrue
    QTrue.new(left.tag)
  end

  # Converts *left* to a string (see `Unary.to_str`), checks
  # whether that string is a substring of *right*, and returns
  # the string. Otherwise, returns `QFalse`.
  def in?(left : Quote, right : QString) : QString | QFalse
    as_str = Unary.to_str(left)

    right.value.includes?(as_str.value) ? as_str : QFalse.new(left.tag)
  end

  # Checks if *left* is an item of *right* (via `is?(left, item)`).
  # Returns **the item**, or `QFalse`.
  def in?(left : Quote, right : QVector) : Quote
    right.items.each do |item|
      unless is?(left, item).false?
        return item.false? ? QTrue.new(item.tag) : item
      end
    end

    QFalse.new(left.tag)
  end

  # Returns `QFalse`.
  def in?(left : Quote, right : Quote)
    QFalse.new(left.tag)
  end

  # Compares two numbers, *left* and *right*, and returns `QTrue`/
  # `QFalse`, depending on the outcome. Valid *operator*s are:
  # `<`, `>`, `<=`, `>=`. Raises if *operator* is invalid.
  def cmp(operator : String, left : QNumber, right : QNumber)
    l = left.value
    r = right.value

    case operator
    when "<"
      l < r ? QTrue.new(left.tag) : QFalse.new(left.tag)
    when ">"
      l > r ? QTrue.new(left.tag) : QFalse.new(left.tag)
    when "<="
      l <= r ? QTrue.new(left.tag) : QFalse.new(left.tag)
    when ">="
      l >= r ? QTrue.new(left.tag) : QFalse.new(left.tag)
    else
      raise "cmp: invalid operator"
    end
  end

  # Compares the lengths (see `Unary.to_len`) of *left*, *right*
  # using *operator*. For a list of valid operators, see `cmp`
  # for two numbers.
  def cmp(operator, left : QString, right : QString)
    cmp(operator,
      Unary.to_len(left),
      Unary.to_len(right))
  end

  # Compares numericized (see `Unary.to_num`) *left*, *right*
  # using *operator*. May return nil if weren't able to convert
  # *left*/*right* to number.
  #
  # For a list of valid operators, see `cmp(..., QNumber, QNumber)`.
  def cmp(operator, left : Quote, right : Quote)
    cmp(operator,
      Unary.to_num(left) || return,
      Unary.to_num(right) || return)
  end

  # Applies a binary numeric *operator* to numbers *left*,
  # *right*. Valid *operator*s are: `+`, `-`, `*`, `/`. Raises
  # if *operator* is invalid. **Does not catch division by zero.**
  def binum(operator : String, left : QNumber, right : QNumber) : QNumber
    l = left.value
    r = right.value

    case operator
    when "+"
      QNumber.new(left.tag, l + r)
    when "-"
      QNumber.new(left.tag, l - r)
    when "*"
      QNumber.new(left.tag, l * r)
    when "/"
      QNumber.new(left.tag, l / r)
    else
      raise "binum: invalid operator"
    end
  end

  # Converts *left*, *right* to numbers (see `Unary.to_num`),
  # and passes them (together with *operator*) to `binum`.
  def binum(operator, left : Quote, right : Quote) : QNumber?
    binum(operator,
      Unary.to_num(left) || return,
      Unary.to_num(right) || return)
  end

  # Concatenates two vectors, *left* and *right*. Returns the
  # resulting vector.
  def veccat(left : QVector, right : QVector) : QVector
    QVector.new(left.tag, left.items + right.items, filter: nil)
  end

  # Converts *left*, *right* to vectors (see `Unary.to_vec`),
  # and passes them to `veccat`.
  def veccat(left : Quote, right : Quote) : QVector
    veccat(
      Unary.to_vec(left),
      Unary.to_vec(right),
    )
  end

  # Concatenates two strings, *left* and *right*. Returns the
  # resulting string.
  def strcat(left : QString, right : QString) : QString
    QString.new(left.tag, left.value + right.value)
  end

  # Converts *left*, *right* to strings (see `Unary.to_str`),
  # and passes them to `strcat`.
  def strcat(left : Quote, right : Quote) : QString
    strcat(
      Unary.to_str(left),
      Unary.to_str(right)
    )
  end

  # Repeats string *left* *right* times. Raises `OverflowError`
  # if *right* is bigger than `Int32::MAX`.
  def repeat(left : QString, right : QNumber) : QString
    l = left.value
    r = right.value.to_big_i

    # Although Int32::MAX is a big number and it's dangerous
    # to make such a long string, it's still safer than the
    # limitless BigDecimal.
    raise OverflowError.new if r >= Int32::MAX

    QString.new(left.tag, l * r)
  end

  # Concatenates *left* to itself *right* times. Raises
  # `OverflowError` if *right* is bigger than `Int32::MAX`.
  def repeat(left : QVector, right : QNumber) : QVector
    l = left.items
    r = right.value.to_big_i

    # Although Int32::MAX is a big number and it's dangerous
    # to make such a long vector, it's still safer than the
    # limitless BigDecimal.
    raise OverflowError.new if r >= Int32::MAX

    QVector.new(left.tag, l * r, filter: nil)
  end

  # Converts *left* to number (see `Unary.to_num`), and calls
  # `repeat(right, left)`.
  def repeat(left : Quote, right : QString)
    repeat(right, Unary.to_num(left) || return)
  end

  # :ditto:
  def repeat(left : Quote, right : QVector)
    repeat(right, Unary.to_num(left) || return)
  end

  # Converts *left* to vector (see `Unary.to_vec`), *right* to
  # number (see `Unary.to_num`), and calls `repeat(left, right)`.
  def repeat(left : Quote, right : Quote) : MaybeQuote
    repeat(
      Unary.to_vec(left),
      Unary.to_num(right) || return,
    )
  end

  # Applies binary *operator* to *left*, *right*, and returns
  # the result. Returns nil if the operation failed.
  def binary(operator : String, left : Quote, right : Quote) : MaybeQuote
    case operator
    when "and" then conj(left, right)
    when "or"  then disj(left, right)
    when "is"  then is?(left, right)
    when "in"  then in?(left, right)
    when "&"   then veccat(left, right)
    when "~"   then strcat(left, right)
    when "x"   then repeat(left, right)
    when "<", ">", "<=", ">="
      cmp(operator, left, right)
    when "+", "-", "*", "/"
      binum(operator, left, right)
    end
  end
end
