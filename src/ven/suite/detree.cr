require "./*"

module Ven::Suite
  # A visitor that provides **detreeing**, which means converting
  # a `Quote` back into source code.
  class Detree < Visitor(String)
    @indent = 0

    # Returns an empty string if *condition* is false. Otherwise,
    # returns *value*.
    private macro maybe(value, if condition)
      {{condition}} ? {{value}} : ""
    end

    # Executes the block with increased indentation level.
    #
    # Returns whatever the block returned.
    private macro indented
      @indent += 2
      result = {{yield}}
      @indent -= 2
      result
    end

    # Makes *quotes* formatted and comma-separated.
    private macro commaed(quotes)
      visit({{quotes}}).join(", ")
    end

    # Visits *quotes* with respect to indentation.
    #
    # Prepends a newline.
    private def i_visit(quotes : Quotes)
      indented do
        String.build do |buffer|
          buffer << "\n" << quotes.map { |quote| "#{" " * @indent}#{visit(quote)}" }.join(";\n")
        end
      end
    end

    # Visits *quote* with respect to indentation.
    private def i_visit(quote : QBlock)
      visit(quote)
    end

    # :ditto:
    private def i_visit(quote)
      indented do
        "\n#{" " * @indent}#{visit(quote)}"
      end
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

    def visit!(q : QUPop)
      "_"
    end

    def visit!(q : QURef)
      "&_"
    end

    def visit!(q : QUnary)
      String.build do |buffer|
        buffer << "("

        if q.operator == "not"
          buffer << q.operator << " " << "(" << visit(q.operand) << ")"
        else
          buffer << q.operator << visit(q.operand)
        end

        buffer << ")"
      end
    end

    def visit!(q : QBinary)
      String.build do |buffer|
        left, right = q.left, q.right

        if left.is_a?(QAssign) || left.is_a?(QBinaryAssign)
          buffer << "(" << visit(q.left) << ")"
        else
          buffer << visit(q.left)
        end

        buffer << " " << q.operator << " "

        if right.is_a?(QAssign) || right.is_a?(QBinaryAssign)
          buffer << "(" << visit(q.right) << ")"
        else
          buffer << visit(q.right)
        end
      end
    end

    def visit!(q : QAssign)
      "#{q.target} #{q.global ? ":=" : "="} #{visit(q.value)}"
    end

    def visit!(q : QBinaryAssign)
      "#{q.target} #{q.operator}= #{visit(q.value)}"
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
      "#{q.target}++"
    end

    def visit!(q : QReturnDecrement)
      "#{q.target}--"
    end

    # Formats field *accessor*.
    private def field(accessor : FAImmediate)
      accessor.access
    end

    # :ditto:
    private def field(accessor : FADynamic)
      "(#{visit(accessor.access)})"
    end

    # :ditto:
    private def field(accessor : FABranches)
      visit(accessor.access) # QVector
    end

    # Formats field *accessors*.
    private def field(accessors : FieldAccessors)
      accessors.map { |x| field(x) }.join(".")
    end

    def visit!(q : QAccessField)
      "(#{visit(q.head)}).#{field(q.tail)}"
    end

    def visit!(q : QReduceSpread)
      "|#{q.operator}| #{visit(q.operand)}"
    end

    def visit!(q : QMapSpread)
      "|#{visit(q.operator)}|#{maybe(":", if: q.iterative)} #{visit(q.operand)}"
    end

    def visit!(q : QIf)
      blocky = q.suc.is_a?(QBlock)

      String.build do |buffer|
        buffer << "if (" << visit(q.cond) << ") " << i_visit(q.suc)

        if alt = q.alt
          if blocky
            buffer << " "
          else
            buffer << "\n" << " " * @indent
          end

          buffer << "else "

          if alt.is_a?(QIf)
            buffer << visit(alt)
          else
            buffer << i_visit(alt)
          end
        end
      end
    end

    def visit!(q : QBlock)
      "{#{i_visit(q.body)}\n#{" " * @indent}}"
    end

    def visit!(q : QGroup)
      visit(q.body).join(";\n")
    end

    def visit!(q : QEnsure)
      "ensure #{visit(q.expression)}"
    end

    def visit!(q : QFun)
      equals = q.body.size == 1

      String.build do |buffer|
        buffer << "fun " << q.name << "(" << q.params.join(", ") << maybe(", *", if: q.slurpy) << ")"
        buffer << " given " << commaed(q.given) unless q.given.empty?

        if equals
          buffer << " =" << i_visit(q.body)
        else
          buffer << " {" << i_visit(q.body) << "\n" << " " * @indent << "}"
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

    def visit!(q : QReturnStatement | QReturnExpression)
      "return #{visit(q.value)}"
    end

    def visit!(q : QBox)
      String.build do |buffer|
        buffer << "box " << q.name << "(" << q.params.join(", ") << ")"

        unless q.given.empty?
          buffer << " given #{commaed(q.given)}"
        end

        unless q.namespace.empty?
          buffer << "{\n"

          indented do
            q.namespace.each do |name, value|
              buffer << " " * @indent << name << " = " << visit(value) << ";\n"
            end
          end

          buffer << "}"
        end
      end
    end

    def visit!(q : QDistinct)
      "distinct #{q.pieces.join(".")}"
    end

    def visit!(q : QExpose)
      "expose #{q.pieces.join(".")}"
    end

    # Returns the detreed *quotes*.
    def self.detree(quotes : Quotes)
      new.visit(quotes).join(";\n")
    end
  end
end
