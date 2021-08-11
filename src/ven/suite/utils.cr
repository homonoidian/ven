module Ven::Suite::Utils
  extend self

  # Colorizes a *snippet* of Ven code.
  #
  # - Keywords are blue.
  # - Numbers are magenta.
  # - Strings, regexes are yellow.
  def highlight(snippet : String, context : CxReader)
    Reader.words(snippet, context).map do |word|
      lexeme = word.lexeme

      case word.type
      when "STRING", "REGEX"
        lexeme.colorize.yellow
      when "NUMBER"
        lexeme.colorize.magenta
      when "IGNORE"
        lexeme.colorize.dark_gray
      when "$SYMBOL"
        lexeme.colorize.green
      when "KEYWORD"
        lexeme.colorize.blue
      else
        lexeme
      end
    end.join
  end

  # Colorizes a Ven *model*, in the style of `highlight(snippet)`.
  #
  # - `Vec` is highlighted recursively.
  # - `MMap` keys are highlighted yellow, values recursively.
  # - Unsupported models are left unhighlighted.
  def highlight(model : Model) : String
    str = model.to_s

    case model
    when Num
      str.colorize.magenta
    when Str, MRegex
      str.colorize.yellow
    when Vec
      "[#{model.items.join(", ") { |item| highlight(item) }}]"
    when MBool
      str.colorize.blue
    when MMap
      "%{#{model.map.join(", ") { |(k, v)| "#{k.colorize.yellow} #{highlight(v)}" }}}"
    else
      str
    end.to_s
  end

  # Returns `{span.total_<unit>, <unit>}`, choosing the most
  # appropriate unit starting with nanoseconds, and ending
  # with seconds.
  def with_unit(span : Time::Span)
    if (ns = span.total_nanoseconds) < 1000
      {ns, "ns"}
    elsif (us = span.total_microseconds) < 1000
      {us, "us"}
    elsif (ms = span.total_milliseconds) < 1000
      {ms, "ms"}
    else
      {span.total_seconds, "sec"}
    end
  end
end
