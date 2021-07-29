# The facilities needed for a readtime builtin to thrive.
struct Ven::Suite::Readtime::Builtin
  def initialize(
    @caller : ReadExpansion,
    @state : State,
    @reader : Reader,
    @parent : Parselet::Parselet
  )
  end

  # A shorthand for `callable(form || return, form || return, ...)`
  private macro apply!(callable, *forms)
    {{callable}}(
      {% for form in forms %}
        {{form}} || return,
      {% end %}
    )
  end

  # Stringifies (see `Unary.to_str`) and outputs each quote
  # of *quotes* to STDOUT. If *quotes* consists of one quote,
  # returns this quote. Otherwise, wraps *quotes* in a vector.
  def say(quotes : Quotes)
    quotes.each do |quote|
      puts Unary.to_str(quote).value
    end

    case quotes.size
    when 0
      # Some sort of @reader.tag instead of void tag?
      QVector.new(QTag.void, [] of Quote)
    when 1
      quotes.first
    else
      QVector.new(quotes[0].tag, quotes)
    end
  end

  # Temporary, covers the unsupported `operand[]`.
  def chars(operand : QString)
    chars = operand.value.chars.map do |char|
      QString.new(operand.tag, char.to_s).as(Quote)
    end

    QVector.new(operand.tag, chars)
  end

  # :ditto:
  def chars(operand)
  end

  # Temporary, covers the unsupported `operand[from -1]`.
  def reverse(operand : QString)
    QString.new(operand.tag, operand.value.reverse)
  end

  # :ditto:
  def reverse(operand)
  end

  # Reads a curly block (see `Parselet.block`). Makes semicolon
  # optional for the parent nud macro.
  def curly_block
    QBlock.new(@parent.tag, @parent.block)
  end

  # Reads a loose block (an '=' followed by an expression with
  # `Precedence::ZERO`). Makes semicolon required for the parent
  # nud macro.
  def loose_block
    body = @reader.after("=") { @reader.led(Precedence::PREFIX) }

    # `parse!` of `Nud` and `Led` reset this after each parse,
    # so there are almost no worries this will conflict with a
    # semicolon decision made inside *body*.
    @parent.semicolon = true

    QBlock.new(body.tag, [body])
  end

  # Reads a tight block (an expression with `Precedence::PREFIX`).
  # Makes semicolon required for the parent nud macro.
  def tight_block
    body = @reader.led(Precedence::PREFIX)

    # `parse!` of `Nud` and `Led` reset this after each parse,
    # so there are almost no worries this will conflict with a
    # semicolon decision made inside *body*.
    @parent.semicolon = true

    QBlock.new(body.tag, [body])
  end

  # Depending on the current word, reads either a `curly_block`
  # (if the current word is '{'), a `loose_block` ('='), or a
  # `tight_block` (none of the mentioned).
  def block
    case @reader
    when .word?("{") then curly_block
    when .word?("=") then loose_block
    else
      tight_block
    end
  end

  # Calls readtime builtin *name* with the given *args*.
  def do(name : String, args : Quotes)
    case name
    when "say"         then say(args)
    when "chars"       then apply!(chars, args[0]?)
    when "reverse"     then apply!(reverse, args[0]?)
    when "block"       then block
    when "curly-block" then curly_block
    when "tight-block" then tight_block
    when "loose-block" then loose_block
    end
  end
end
