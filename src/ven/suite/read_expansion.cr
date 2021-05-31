require "./*"

module Ven::Suite
  class ReadExpansion < Visitor(Quote)
    @definitions : Hash(String, Quote)

    def initialize(@definitions)
    end

    private macro defvisit!(type, *names)
      def visit!(%quote : {{type}})
        {% for name in names %}
          {% if name.is_a?(TypeDeclaration) %}
            apply to: %quote.{{name.var}}, as: {{name.type}}
          {% else %}
            apply to: %quote.{{name}}
          {% end %}
        {% end %}

        %quote
      end
    end

    private macro defvisit!(type)
      def visit!(%quote : {{type}})
        %quote
      end
    end

    private macro defvisit(type, &block)
      def visit!(%quote : {{type}})
        {{*block.args}} = %quote
        {{yield}}
        %quote
      end
    end

    private macro apply(to quote, as assert = nil)
      {{quote}} = visit({{quote}})
        {% if assert %}
          .as({{assert}})
        {% end %}
    end

    # Given a *message*, dies of read error that is assumed
    # to be at the start of the current quote.
    def die(message : String)
      raise ReadError.new(@last.tag, message)
    end

    # Substitutes itself with the quote it was assigned.
    def visit!(q : QReadtimeSymbol)
      @definitions[q.value]? ||
        die("there is no readtime symbol named '$#{q.value}'")
    end

    defvisit QIf do |quote|
      apply to: quote.cond
      apply to: quote.suc
      quote.alt = quote.alt.try { |it| visit(it) }
    end

    # TODO:
    # defvisit QBox do |quote|
    #   apply to: quote.name, as: QSymbol
    #   apply to: quote.given
    #   quote.namespace = quote.namespace.to_h do |pair|
    #     { visit(pair[0]).as(QSymbol),
    #       visit(pair[1]).as(Quote) }
    #   end
    # end

    defvisit! QString
    defvisit! QRegex
    defvisit! QNumber
    defvisit! QURef
    defvisit! QUPop
    defvisit! QRuntimeSymbol
    defvisit! QReturnQueue

    defvisit! QVector, items
    defvisit! QUnary, operand
    defvisit! QBinary, left, right
    defvisit! QCall, callee, args
    defvisit! QAssign, target : QSymbol, value
    defvisit! QBinaryAssign, target : QSymbol, value
    defvisit! QReturnDecrement, target : QSymbol
    defvisit! QReturnIncrement, target : QSymbol
    defvisit! QDies, operand
    defvisit! QIntoBool, operand
    defvisit! QMapSpread, operator, operand
    defvisit! QReduceSpread, operand
    defvisit! QGroup, body
    defvisit! QBlock, body
    # TODO: defvisit! QFun, name : QSymbol, given, body
    defvisit! QEnsure, expression
    defvisit! QQueue, value
    defvisit! QInfiniteLoop, repeatee
    defvisit! QAccessField, head # TODO: FieldAccessor
    defvisit! QBaseLoop, base, repeatee
    defvisit! QStepLoop, base, step, repeatee
    defvisit! QComplexLoop, start, base, step, repeatee
    defvisit! QNext, args
    defvisit! QReturnStatement, value
    defvisit! QReturnExpression, value
  end
end
