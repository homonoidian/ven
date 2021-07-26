struct Ven::Suite::Readtime::Builtin
  # TODO pretty!

  def initialize(@caller : ReadExpansion, @reader : Reader)
    # todo take state too
  end

  macro apply!(callable, *forms)
    {{callable}}(
      {% for form in forms %}
        {{form}} || return,
      {% end %}
    )
  end

  def say(quotes : Quotes)
    quotes.each do |quote|
      puts Unary.to_str(quote).value
    end

    case quotes.size
    when 0
      # Some sort of @reader.tag instead of void tag?
      QVector.new(QTag.void, [] of Quote, filter: nil)
    when 1
      quotes.first
    else
      QVector.new(quotes[0].tag, quotes, filter: nil)
    end
  end

  def chars(operand : QString)
    chars = operand.value.chars.map do |char|
      QString.new(operand.tag, char.to_s).as(Quote)
    end

    QVector.new(operand.tag, chars, filter: nil)
  end

  def chars(operand)
  end

  def reverse(operand : QString)
    QString.new(operand.tag, operand.value.reverse)
  end

  def reverse(operand)
  end

  def do(name : String, args : Quotes)
    case name
    when "say"     then say(args)
    when "chars"   then apply!(chars, args[0]?)
    when "reverse" then apply!(reverse, args[0]?)
    end
  end
end
