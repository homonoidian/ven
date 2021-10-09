require "./suite/*"

module Ven
  # A quote visitor that produces Ven unstitched chunks.
  #
  # Ven bytecode instructions (`Instruction`) are organized
  # into *snippets* (`Snippet`), which themselves are grouped
  # into *chunks* (`Chunk`). It is the snippets' delimitation
  # that makes us call the chunks *unstitched*.
  #
  # The boundaries between snippets are dissolved during the
  # process of *stitching*. Once this process is finished,
  # the chunks are thought of as *stitched*.
  #
  # ```
  # puts Compiler.compile(quotes) # ==> unstitched chunks
  # ```
  class Compiler < Suite::Visitor(Nil)
    include Suite

    # The chunks of this compiler.
    property chunks = Chunks.new
    # Whether or not to compile ensure tests.
    property ensure_tests = false

    # A label that points to the body of the nearest surrounding
    # loop (if any).
    @loop : Label?
    # Offset of the target chunk (i.e., chunk-of-emission).
    @target = 0
    # Nearest surrounding function (if any).
    @function : VFunction?

    def initialize(@file = "untitled", @context = CxCompiler.new)
      @target = @chunks.size
      @chunks << Chunk.new(@file, "<unit>")
    end

    # Given an explanation message, *message*, dies of `CompileError`.
    private def die(message : String)
      traces = @context.traces.dup

      # If the last entry in traces does not point to the
      # entity that had actually caused the death, insert
      # one.
      unless traces.last? == @last.tag
        traces << Trace.new(@last.tag, "unit")
      end

      raise CompileError.new(traces, message)
    end

    # Makes a label.
    private macro label
      Label.new
    end

    # Makes *variable* be *value* in the block. Restores the
    # old value once out of the block.
    private macro having(variable, be value, &block)
      %previous, {{variable}} = {{variable}}, {{value}}

      begin
        {{yield}}
      ensure
        {{variable}} = %previous
      end
    end

    # Returns the chunk at *cursor*. Defaults to the target chunk.
    private macro chunk(at cursor = @target)
      @chunks[{{cursor}}]
    end

    # Introduces a chunk named *name*. Makes the target chunk
    # be this new chunk for the duration of the block.
    #
    # The block may choose to receive the target chunk offset
    # as an argument.
    private macro under(chunk name, &block)
      having @target, be: @chunks.size do
        @chunks << Chunk.new(@file, {{name}})

        {% if block.args %}
          {{*block.args}} = @target
        {% end %}

        {{yield}}
      end
    end

    # Tells the chunk-of-emission that a new label, *label*,
    # starts here.
    private macro label(label)
      chunk.label({{label}})
    end

    # Issues an instruction into the chunk-of-emission.
    #
    # *opcode* and *argument* are the opcode and argument of
    # that instruction.
    #
    # Ensures *opcode* is not nil.
    private macro issue(opcode, argument = nil)
      chunk.add({{opcode}}.not_nil!, {{argument}}, @last.tag.line)
    end

    # Makes a `VSymbol` called *name* and with nest *nest*.
    #
    # Tries to figure out its nest. If failed, produces
    # `mksym`-like behavior.
    private macro sym(name, nest = -1)
      %name = {{name}}
      %nest = @context.bound?(%name)
      mksym(%name, %nest || {{nest}})
    end

    # Makes  a `VSymbol` called *name* and with nest *nest*.
    private macro mksym(name, nest = -1)
      VSymbol.new({{name}}, {{nest}})
    end

    # Issues the appropriate field gathering instructions
    # for field accessor *accessor*.
    private def field!(accessor : FAImmediate)
      issue(Opcode::FIELD_IMMEDIATE, accessor.access.value)
    end

    # :ditto:
    private def field!(accessor : FADynamic)
      visit(accessor.access)
      issue(Opcode::FIELD_DYNAMIC)
    end

    # :ditto:
    private def field!(accessor : FABranches)
      branches = accessor.access.items

      branches.each_with_index do |branch, index|
        issue(Opcode::SWAP) unless index == 0
        issue(Opcode::DUP) unless index == branches.size - 1

        if branch.is_a?(QAccessField)
          field! [FADynamic.new(branch.head)] + branch.tail
        elsif branch.is_a?(QRuntimeSymbol)
          field! FAImmediate.new(branch)
        else
          field! FADynamic.new(branch)
        end
      end

      issue(Opcode::VEC, branches.size)
    end

    # Emits the appropriate field gathering instructions
    # for *accessors*, an array of field accessors.
    private def field!(accessors : FieldAccessors)
      accessors.each { |accessor| field!(accessor) }
    end

    # Passes without returning anything.
    def visit(quote : QVoid)
    end

    # Visits each quote of *quotes*.
    def visit(quotes : Quotes)
      quotes.each { |quote| visit(quote) }
    end

    def visit!(q : QRuntimeSymbol)
      issue(Opcode::SYM, sym q.value)
    end

    def visit!(q : QNumber)
      issue(Opcode::NUM, q.value)
    end

    def visit!(q : QString)
      issue(Opcode::STR, q.value)
    end

    def visit!(q : QRegex)
      issue(Opcode::PCRE, q.value)
    end

    def visit!(q : QVector)
      visit(q.items)
      issue(Opcode::VEC, q.items.size)
    end

    def visit!(q : QTrue)
      issue(Opcode::TRUE)
    end

    def visit!(q : QFalse)
      issue(Opcode::FALSE)
    end

    def visit!(q : QSuperlocalTake)
      issue(Opcode::STAKE)
    end

    def visit!(q : QSuperlocalTap)
      issue(Opcode::STAP)
    end

    def visit!(q : QUnary)
      visit(q.operand)

      opcode =
        case q.operator
        when "+"    then Opcode::TON
        when "-"    then Opcode::NEG
        when "~"    then Opcode::TOS
        when "#"    then Opcode::LEN
        when "&"    then Opcode::TOV
        when "%"    then Opcode::TOM
        when "^"    then Opcode::TAP_SFILL
        when "not"  then Opcode::TOIB
        when "to"   then Opcode::TOR_BL
        when "from" then Opcode::TOR_EL
        end

      issue(opcode)
    end

    def visit!(q : QBinary)
      finish = label

      visit(q.left)

      if finishable = q.operator == "and"
        issue(Opcode::JIF_ELSE_POP, finish)
      elsif finishable = q.operator == "or"
        issue(Opcode::JIT_ELSE_POP, finish)
      end

      visit(q.right)

      unless finishable
        return issue(Opcode::BINARY, q.operator)
      end

      label finish
    end

    def visit!(q : QAssign)
      return unless target = q.target.as?(QSymbol)

      visit(q.value)
      @context.bound(target.value) if q.global
      issue(Opcode::TAP_ASSIGN, sym target.value)
    end

    def visit!(q : QBinaryAssign)
      return unless target = q.target.as?(QSymbol)

      symbol = sym(target.value)

      visit(q.value)
      issue(Opcode::SYM, symbol)
      issue(Opcode::BINARY_ASSIGN, q.operator)
      issue(Opcode::POP_ASSIGN, symbol)
    end

    def visit!(q : QCall)
      visit(q.callee)
      visit(q.args)
      issue(Opcode::CALL, q.args.size)
    end

    def visit!(q : QDies)
      finish = label
      truthy = label
      falsey = label

      issue(Opcode::SETUP_DIES, truthy)
      visit(q.operand)
      issue(Opcode::J, falsey)
      label truthy
      issue(Opcode::TRUE)
      issue(Opcode::J, finish)
      label falsey
      issue(Opcode::FALSE)
      label finish
      issue(Opcode::RESET_DIES)
    end

    def visit!(q : QIntoBool)
      visit(q.operand)
      issue(Opcode::TOB)
    end

    def visit!(q : QReturnIncrement)
      issue(Opcode::INC, sym q.target.value)
    end

    def visit!(q : QReturnDecrement)
      issue(Opcode::DEC, sym q.target.value)
    end

    def visit!(q : QAccess)
      visit(q.head)
      visit(q.args)
      issue(Opcode::ACCESS, q.args.size)
    end

    def visit!(q : QAccessField)
      visit(q.head)
      field!(q.tail)
    end

    def visit!(q : QReduceSpread)
      visit(q.operand)
      issue(Opcode::REDUCE, q.operator)
    end

    def visit!(q : QIf)
      finish = label
      else_b = label

      visit(q.cond)

      issue(Opcode::IF_SFILL)

      if alt = q.alt
        issue(Opcode::JIF, else_b)
        visit(q.suc)
        issue(Opcode::J, finish)
        label else_b
        visit(alt)
      else
        issue(Opcode::JIF_ELSE_POP, finish)
        visit(q.suc)
      end

      label finish
    end

    def visit!(q : QBlock)
      @context.child do
        under chunk: "<block>" do |target|
          visit(q.body)
          issue(Opcode::RET)
        end

        issue(Opcode::GOTO, target)
      end
    end

    def visit!(q : QGroup)
      visit(q.body)
    end

    def visit!(q : QEnsure)
      visit(q.expression)
      issue(Opcode::ENS)
    end

    def visit!(q : QFun)
      name = q.name.value
      params = q.params

      # Safe to use in this particular case, as we don't have
      # the data it requires, and we don't want to deal with
      # nils, and we want it to be bound to this scope!
      function = uninitialized VFunction

      latter = nil

      # Issue bytecode for the givens. They're required to
      # be on the stack before we execute `FUN`.
      params.givens.each do |given|
        next issue(Opcode::ANY) unless subject = given || latter
        # We don't want to redefine *latter* if the 'unless'
        # succeeds, so *subject*.
        visit(latter = subject)
      end

      # A concrete is bound to the scope where it was first
      # created. And, because of this, a generic is bound to
      # the scope of its first ever concrete.
      unless @context.bound?(name)
        @context.bound(name)
      end

      @context.trace(q.tag, name) do
        @context.child do
          under chunk: name do |target|
            function = VFunction.new(
              sym(name),
              # Body (target) chunk:
              target,
              # Parameter names (or '?'s; used for the string
              # representation, and nothing else!)
              params.names,
              # How many values 'given'?
              params.size,
              # How many parameters required?
              params.required.size,
              # Is it slurpy?
              params.slurpy?,
            )

            params.reverse_each do |param|
              case param
              when .pattern
                issue(Opcode::DUP)
                visit(param.pattern.not_nil!)
                issue(Opcode::SWAP)
                issue(Opcode::CALL, 1)
                issue(Opcode::MATCH, param.index)
              when .slurpy
                issue(Opcode::REST, param.index)
              when .underscore
                # `fun <>(_) = <>` does look like it ignores,
                # but it doesn't. It fills a superlocal. You
                # can *really* ignore a parameter in Ven.
                issue(Opcode::POP_SFILL)
              when .name
                # If it has a name, assign in the local scope.
                issue(Opcode::POP_ASSIGN, mksym param.name.not_nil!)
              else
                raise InternalError.new("unknown parameter/-property combination")
              end
            end

            # Visit the body insoway `return`s and `next`s
            # inside know not just that they're, well, inside,
            # but also what they're inside.
            having @function, be: function do
              visit(q.body)
            end

            issue(Opcode::RET)
          end
        end
      end

      issue(Opcode::FUN, function)
    end

    def visit!(q : QInfiniteLoop)
      start = label

      label start

      having @loop, be: start do
        visit(q.repeatee)
      end

      issue(Opcode::POP)
      issue(Opcode::J, start)
    end

    def visit!(q : QBaseLoop)
      start = label
      stop = label

      label start
      visit(q.base)
      issue(Opcode::JIF, stop)

      # Pop previous q.repeatee, if any.
      #
      # FIXME: bug-prone if loop becomes an expression.
      #
      issue(Opcode::TRY_POP)

      having @loop, be: start do
        visit(q.repeatee)
      end

      issue(Opcode::J, start)

      label stop
      issue(Opcode::FALSE_IF_EMPTY)
    end

    def visit!(q : QStepLoop)
      start = label
      stop = label

      label start
      visit(q.base)
      issue(Opcode::JIF, stop)
      issue(Opcode::TRY_POP)

      having @loop, be: start do
        visit(q.repeatee)
      end

      visit(q.step)
      issue(Opcode::POP)
      issue(Opcode::J, start)

      label stop
      issue(Opcode::FALSE_IF_EMPTY)
    end

    def visit!(q : QComplexLoop)
      start = label
      stop = label

      visit(q.start)
      issue(Opcode::POP)

      label start
      visit(q.base)
      issue(Opcode::JIF, stop)
      issue(Opcode::TRY_POP)

      having @loop, be: start do
        visit(q.repeatee)
      end

      visit(q.step)
      issue(Opcode::POP)
      issue(Opcode::J, start)

      label stop
      issue(Opcode::FALSE_IF_EMPTY)
    end

    def visit!(q : QNext)
      args = q.args
      scope = q.scope

      if !(function = @function) && !(loop = @loop)
        die("'next' outside of a loop or a function")
      elsif function && scope.in?("fun", nil)
        issue(Opcode::SYM, function.symbol)
        visit(args)
        issue(Opcode::NEXT_FUN, args.size)
      elsif loop && scope.in?("loop", nil)
        visit(args)
        issue(Opcode::J, loop)
      end
    end

    def visit!(q : QReturnStatement | QReturnExpression)
      die("'return' outside of function") unless @function

      visit(q.value)

      if q.is_a?(QReturnStatement)
        issue(Opcode::FORCE_RET)
      else
        issue(Opcode::SETUP_RET)
      end
    end

    def visit!(q : QReturnQueue)
      die("'return' outside of function") unless @function

      issue(Opcode::FORCE_RET_QUEUE)
    end

    def visit!(q : QBox)
      name = q.name.value
      params = q.params

      # Boxes and functions are just too similar to make them
      # different under the hood.
      box = uninitialized VFunction

      latter = nil

      # Issue bytecode for the givens. They're required to
      # be on the stack before we execute `BOX`.
      params.givens.each do |given|
        next issue(Opcode::ANY) unless subject = given || latter
        # We don't want to redefine *latter* if the 'unless'
        # succeeds, so *subject*.
        visit(latter = subject)
      end

      # Much like a concrete, a box is bound to the scope
      # where it was first created.
      unless @context.bound?(name)
        @context.bound(name)
      end

      @context.child do
        under chunk: name do |target|
          box = VFunction.new(
            sym(name),
            # Body (target) chunk:
            target,
            # Parameter names (or '?'s; used for the string
            # representation, and nothing else!)
            params.names,
            # How many values 'given'?
            params.size,
            # How many parameters required?
            params.required.size,
            # Is it slurpy?
            false
          )

          params.reverse_each do |param|
            case param
            when .pattern
              issue(Opcode::DUP)
              visit(param.pattern.not_nil!)
              issue(Opcode::SWAP)
              issue(Opcode::CALL, 1)
              issue(Opcode::MATCH, param.index)
            when .name
              # If it has a name, assign in the local scope.
              issue(Opcode::POP_ASSIGN, mksym param.name.not_nil!)
            else
              raise InternalError.new("unknown parameter/-property combination")
            end
          end

          # Unpack the box namespace - it's simply a bunch
          # of assignments.
          q.namespace.each do |name, value|
            visit(value)
            issue(Opcode::POP_ASSIGN, mksym name.value)
          end

          # When this chunk is called, a new instance of
          # this box is returned. SYM is there so BOX_INSTANCE
          # knows who it's an instance of.
          issue(Opcode::SYM, sym name)
          issue(Opcode::BOX_INSTANCE)
          issue(Opcode::RET)
        end
      end

      issue(Opcode::BOX, box)
      issue(Opcode::POP_ASSIGN, sym name)
    end

    def visit!(q : QLambda)
      slurpy = q.slurpy
      params = q.params

      lambda = uninitialized VFunction

      aritious = params.reject("*")
      arity = aritious.size

      @context.child do
        under chunk: "lambda" do |target|
          lambda = VFunction.new(
            VSymbol.nameless,
            # Body (target) chunk:
            target,
            # Parameter names (used for the string representation,
            # and nothing else!)
            params,
            # How many values 'given'?
            0,
            # How many parameters required?
            arity,
            # Is it slurpy?
            slurpy,
          )

          # `Opcode::REST` interprets the slurpie ('*').
          issue(Opcode::REST, arity) if slurpy

          aritious.reverse_each do |param|
            issue(Opcode::POP_ASSIGN, mksym param)
          end

          visit(q.body)
          issue(Opcode::RET)
        end
      end

      issue(Opcode::LAMBDA, lambda)
    end

    def visit!(q : QEnsureTest)
      if @ensure_tests
        visit(q.comment)
        issue(Opcode::TEST_TITLE)
        visit(q.shoulds)
      end

      issue(Opcode::TRUE)
    end

    def visit!(q : QEnsureShould)
      target = uninitialized Int32

      under chunk: "[ensure test: should]" do |target|
        q.pad.each do |quote|
          visit(quote)
          issue(Opcode::TEST_ASSERT)
        end
        issue(Opcode::TEST_SHOULD, q.section)
        issue(Opcode::RET)
      end

      issue(Opcode::GOTO, target)
    end

    def visit!(q : QQueue)
      die("'queue' outside a function") unless @function

      visit(q.value)
      issue(Opcode::QUEUE)
    end

    def visit!(q : QMap)
      q.keys.zip(q.vals) do |key, val|
        visit(key)
        visit(val)
      end
      issue(Opcode::MAP, q.keys.size + q.vals.size)
    end
  end
end
