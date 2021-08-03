module Ven::Suite::Utils
  extend self

  # Colorizes a *snippet* of Ven code.
  #
  # - Keywords are blue.
  # - Numbers are magenta.
  # - Strings, regexes are yellow.
  def highlight(snippet : String)
    words_in(snippet).map do |(type, lexeme)|
      case type
      when :STRING, :REGEX
        lexeme.colorize.yellow
      when :KEYWORD
        lexeme.colorize.blue
      when :NUMBER
        lexeme.colorize.magenta
      when :SPECIAL
        lexeme.colorize.light_gray
      when :IGNORE
        lexeme.colorize.dark_gray
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

  # Returns the word boundaries in *snippet*, excluding
  # the boundaries of the words of IGNORE type.
  def word_boundaries(snippet : String)
    words_in(snippet).compact_map do |(type, lexeme, offset)|
      unless type == :IGNORE
        offset..(offset + lexeme.size)
      end
    end
  end

  # Returns the words of *snippet* in form of an array of
  # `{Symbol, String}`. First is the word type and second
  # is the word lexeme.
  def words_in(snippet : String)
    words = [] of {Symbol, String, Int32}
    offset = 0

    loop do
      case pad = snippet[offset..]
      when .starts_with? Ven.regex_for(:STRING)
        words << {:STRING, $0, offset}
      when .starts_with? Ven.regex_for(:SYMBOL)
        if Reader::KEYWORDS.any?($0)
          words << {:KEYWORD, $0, offset}
        else
          words << {:SYMBOL, $0, offset}
        end
      when .starts_with? Ven.regex_for(:REGEX)
        words << {:REGEX, $0, offset}
      when .starts_with? Ven.regex_for(:NUMBER)
        words << {:NUMBER, $0, offset}
      when .starts_with? Ven.regex_for(:IGNORE)
        words << {:IGNORE, $0, offset}
      when .empty?
        break
      else
        # Pass over unknown characters.
        words << {:UNKNOWN, snippet[offset].to_s, offset}
        offset += 1
        next
      end

      offset += $0.size
    end

    words
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
