require "./*"

module Ven::Suite
  # A visitor that provides **detreeing**, which means converting
  # a `Quote` back into source code.
  class Detree < Visitor(String)
    # These unary operators require a space between them
    # and their operand.
    KEYWORD_UNARIES = {"to", "not", "from"}

    # Current indentation level.
    @indent = 0

    # Yields with increased indentation.
    #
    # Returns whatever the block returned.
    private macro indented
      @indent += 2
      result = {{yield}}
      @indent -= 2
      result
    end

    # Returns visited and comma-separated *quotes*.
    private macro commaed(quotes)
      visit({{quotes}}).join(", ")
    end

    # Returns visited and indented *q*.
    #
    # NOTE: Prepends a newline.
    private def i_visit(q : Quotes)
      indented do
        String.build do |io|
          io << "\n"
          # Go over the quotes, indenting them & appending
          # a ';' & newline.
          q.each_with_index do |quote, index|
            io << " " * @indent << visit(quote)
            io << ";\n" if index < q.size - 1
          end
        end
      end
    end

    # :ditto:
    private def i_visit(q : Quote)
      i_visit([q])
    end

    def visit!(q : QVoid)
      ""
    end

    def visit!(q : QRuntimeSymbol)
      q.value
    end

    def visit!(q : QNumber)
      q.value.to_s
    end

    def visit!(q : QString)
      q.value.inspect
    end

    def visit!(q : QRegex)
      "`#{q.value}`"
    end

    def visit!(q : QVector)
      "[#{commaed(q.items)}]"
    end

    def visit!(q : QTrue)
      "true"
    end

    def visit!(q : QFalse)
      "false"
    end

    def visit!(q : QUPop)
      "_"
    end

    def visit!(q : QURef)
      "&_"
    end

    def visit!(q : QUnary)
      String.build do |io|
        io << "("
        if q.operator.in?(KEYWORD_UNARIES)
          io << q.operator << " " << "(" << visit(q.operand) << ")"
        else
          io << q.operator << visit(q.operand)
        end
        io << ")"
      end
    end

    def visit!(q : QBinary)
      String.build do |io|
        left, right = q.left, q.right

        if left.is_a?(QAssign) || left.is_a?(QBinaryAssign)
          # Don't let `(x = 2) and 3` produce `x = 2 and 3`.
          # Produce `(x = 2) and 3` instead.
          io << "(" << visit(q.left) << ")"
        else
          io << visit(q.left)
        end

        io << " " << q.operator << " "

        if right.is_a?(QAssign) || right.is_a?(QBinaryAssign)
          # Don't let `3 and (x = 2)` produce `3 and x = 2`.
          # Produce `3 and (x = 2)` instead.
          io << "(" << visit(q.right) << ")"
        else
          io << visit(q.right)
        end
      end
    end

    def visit!(q : QAssign)
      "#{visit(q.target)} #{q.global ? ":=" : "="} #{visit(q.value)}"
    end

    def visit!(q : QBinaryAssign)
      "#{visit(q.target)} #{q.operator}= #{visit(q.value)}"
    end

    def visit!(q : QCall)
      "#{visit(q.callee)}(#{commaed(q.args)})"
    end

    def visit!(q : QDies)
      "#{visit(q.operand)} dies"
    end

    def visit!(q : QIntoBool)
      "(#{visit(q.operand)})?"
    end

    def visit!(q : QReturnIncrement)
      "#{visit(q.target)}++"
    end

    def visit!(q : QReturnDecrement)
      "#{visit(q.target)}--"
    end

    # Formats field accessor *accessor*.
    private def field(accessor : FAImmediate)
      visit(accessor.access)
    end

    # :ditto:
    private def field(accessor : FADynamic)
      "(#{visit(accessor.access)})"
    end

    # :ditto:
    private def field(accessor : FABranches)
      visit(accessor.access) # always QVector
    end

    # Formats an array field accessors *accessors*.
    private def field(accessors : FieldAccessors)
      accessors.map { |a| field(a) }.join(".")
    end

    def visit!(q : QAccess)
      "#{visit(q.head)}[#{commaed(q.args)}]"
    end

    def visit!(q : QAccessField)
      "#{visit(q.head)}.#{field(q.tail)}"
    end

    def visit!(q : QReduceSpread)
      "|#{q.operator}| #{visit(q.operand)}"
    end

    def visit!(q : QMapSpread)
      String.build do |io|
        io << "|" << visit(q.operator) << "|"
        io << ":" if q.iterative
        io << " " << visit(q.operand)
      end
    end

    # Formulates a short if from *cond*, *suc* and *alt*.
    #
    # ```ven
    # if (cond) suc else alt
    # ```
    #
    # NOTE: *suc* and *alt* mustn't be blocks.
    private def fmt_short_if(cond : Quote, suc : Quote, alt : Quote)
      "if (#{visit(cond)}) #{visit(suc)} else #{visit(alt)}"
    end

    # :ditto:
    private def fmt_short_if(cond, suc, alt : Nil)
      "if (#{visit(cond)}) #{visit(suc)}"
    end

    # Formulates a long if from *cond*, *suc* and *alt*.
    #
    # ```ven
    # if (cond)
    #   suc
    # else
    #   alt
    # ```
    #
    # NOTE: *suc* and *alt* mustn't be blocks.
    private def fmt_long_if(cond : Quote, suc : Quote, alt : Quote)
      String.build do |io|
        io << "if (" << visit(cond) << ")" << i_visit(suc)
        io << "\n" << " " * @indent << "else" << i_visit(alt)
      end
    end

    # :ditto:
    private def fmt_long_if(cond, suc, alt : Nil)
      "if (#{visit(cond)})#{i_visit(suc)}"
    end

    # Formulates a blocky if.
    #
    # ```ven
    # if (cond) {
    #   suc
    # } else {
    #   alt
    # }
    private def fmt_blocky_if(cond : Quote, suc : QBlock, alt : QBlock)
      "if (#{visit(cond)})#{visit(suc)} else #{visit(alt)}"
    end

    # :ditto:
    private def fmt_blocky_if(cond : Quote, suc : QBlock, alt : Nil)
      "if (#{visit(cond)})#{visit(suc)}"
    end

    def visit!(q : QIf)
      suc = q.suc
      alt = q.alt

      case {suc, alt}
      when {QBlock, QBlock}
        return fmt_blocky_if(q.cond, suc, alt)
      when {_, QBlock}
        return fmt_blocky_if(q.cond, QBlock.new(q.tag, [suc]), alt)
      when {QBlock, _}
        return fmt_blocky_if(q.cond, suc, alt.try { |me| QBlock.new(q.tag, [me]) })
      end

      short = fmt_short_if(q.cond, q.suc, q.alt)

      # If the short form is around 60ch, accept it. Otherwise,
      # generate the block if.
      if short.size <= 60
        return short
      end

      fmt_long_if(q.cond, q.suc, q.alt)
    end

    def visit!(q : QBlock)
      "{#{i_visit(q.body)}\n#{" " * @indent}}"
    end

    def visit!(q : QGroup)
      visit(q.body).reject("").join(";\n")
    end

    def visit!(q : QEnsure)
      "ensure #{visit(q.expression)}"
    end

    private def fmt_params(io, params : Parameters)
      params.each do |param|
        io << "(" if param.index == 0
        if param.slurpy
          io << "*"
        elsif param.contextual
          io << "$"
        else
          io << param.name
        end
        # ')' is just like ',', but at the end.
        io << (param.index == params.size - 1 ? ")" : ", ")
      end
    end

    private def fmt_givens(io, params : Parameters)
      params.each do |param|
        if given = param.given
          io << " given " if param.index == 0
          io << visit(given)
          io << ", " unless param.index == params.givens.size - 1
        end
      end
    end

    def visit!(q : QFun)
      String.build do |io|
        io << "fun " << visit(q.name) \
          << fmt_params(io, q.params) \
            << fmt_givens(io, q.params)
        # Print the body. If it's blocky, use block. If it's
        # not but it's too long (> 60ch), newline and indent.
        # Otherwise, use '='.
        if q.blocky
          io << " " << visit QBlock.new(q.tag, q.body)
        elsif expr = visit(first = q.body.first)
          if expr.size <= 60
            io << " = " << expr
          else
            io << " =" << i_visit(first)
          end
        end
      end
    end

    def visit!(q : QInfiniteLoop)
      "loop #{visit(q.repeatee)}"
    end

    def visit!(q : QBaseLoop)
      "loop (#{visit(q.base)}) #{visit(q.repeatee)}"
    end

    def visit!(q : QStepLoop)
      "loop (#{visit(q.base)}; #{visit(q.step)}) #{visit(q.repeatee)}"
    end

    def visit!(q : QComplexLoop)
      "loop (#{visit(q.start)}; #{visit(q.base)}; #{visit(q.step)}) #{visit(q.repeatee)}"
    end

    def visit!(q : QNext)
      "next #{q.scope || ""} #{commaed(q.args)}"
    end

    def visit!(q : QQueue)
      "queue #{visit(q.value)}"
    end

    def visit!(q : QReturnQueue)
      "return queue"
    end

    def visit!(q : QReturnStatement | QReturnExpression)
      "return #{visit(q.value)}"
    end

    def visit!(q : QBox)
      String.build do |io|
        ns = q.namespace

        io << "box " << visit(q.name) <<
          fmt_params(io, q.params) <<
          fmt_givens(io, q.params)

        unless ns.empty?
          # Again, box namespace is just a block of assignments.
          # Detree it as such.
          assigns = ns.map { |n, v| QAssign.new(q.tag, n, v, false).as(Quote) }
          io << " " << visit QBlock.new(q.tag, assigns)
        end
      end
    end

    def visit!(q : QLambda)
      "((#{q.params.join(", ")}) #{visit(q.body)})"
    end

    def visit!(q : QPatternEnvelope)
      "'#{visit(q.pattern)}"
    end

    def visit!(q : QQuoteEnvelope)
      "quote(#{visit(q.quote)})"
    end

    def visit!(q : QEnsureTest)
      "ensure #{visit(q.comment)} {#{i_visit(q.shoulds)}\n#{" " * @indent}}"
    end

    def visit!(q : QEnsureShould)
      "should #{q.section.inspect} #{i_visit(q.pad)}"
    end

    def self.detree(quote : Quote)
      new.visit(quote)
    end

    # Returns the detreed *quotes*.
    def self.detree(quotes : Quotes)
      new.visit(quotes).reject("").join(";\n")
    end
  end
end
