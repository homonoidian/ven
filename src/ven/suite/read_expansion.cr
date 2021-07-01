require "./*"

module Ven::Suite
  class ReadExpansion < Transformer
    @definitions : Hash(String, Quote)

    def initialize(@definitions)
    end

    # Provides Ven readtime semantics to *quote*.
    def eval(quote)
      die("#{quote.class} unsupported in readtime envelope")
    end

    # :ditto:
    def eval(homoiconic : QNumber | QString | QRegex)
      homoiconic
    end

    # :ditto:
    def eval(q : QVector)
      QVector.new(q.tag, q.items.map { |item| eval(item) }, nil)
    end

    # :ditto:
    def eval(q : QReadtimeSymbol)
      die("you don't have to distinguish readtime symbols in a readtime envelope")
    end

    # :ditto:
    def eval(q : QRuntimeSymbol)
      @definitions[q.value]
    end

    # :ditto:
    def eval(q : QUnary)
      operand = eval(q.operand)

      case q.operator
      when "+"
        case operand
        when QNumber then return operand
        when QString then return QNumber.new(q.tag, operand.value.to_big_d)
        when QVector then return QNumber.new(q.tag, operand.items.size.to_big_d)
        end
      when "-"
        case operand
        when QNumber then return QNumber.new(q.tag, -operand.value)
        when QString then return QNumber.new(q.tag, -operand.value.to_big_d)
        when QVector then return QNumber.new(q.tag, -operand.items.size.to_big_d)
        end
      when "~"
        case operand
        when QNumber then return QString.new(q.tag, operand.value.to_s)
        when QString then return operand
        else
          return QString.new(q.tag, Detree.detree(operand))
        end
      when "#"
        case operand
        when QString then return QNumber.new(q.tag, operand.value.size.to_big_d)
        when QVector then return QNumber.new(q.tag, operand.items.size.to_big_d)
        else
          return QNumber.new(q.tag, Detree.detree(operand).size.to_big_d)
        end
      when "&"
        case operand
        when QVector then return operand
        else
          return QVector.new(q.tag, [operand], nil)
        end
      end

      die("operation not supported")
    end

    # Expands to the quote the symbol was assigned.
    def transform!(q : QReadtimeSymbol)
      @definitions[q.value]? ||
        die("there is no readtime symbol named '$#{q.value}'")
    end

    # Expands to the quote produced by the expression of the
    # readtime envelope.
    def transform!(q : QReadtimeEnvelope)
      eval(q.expression)
    end
  end
end
