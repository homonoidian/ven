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
  # Basic usage:
  # ```
  # puts Compiler.compile(quotes) # ==> unstitched chunks
  # ```
  class Compiler < Suite::Visitor(Nil)
    include Suite

    # A label that points to the body of the nearest surrounding
    # loop (if any).
    @loop : Label?
    # Points to the chunk this compiler is emitting into (chunk-
    # of-emission).
    @target = 0
    # Nearest surrounding function (if any).
    @function : VFunction?

    # Makes a compiler.
    #
    # No arguments are required, but *file* (for a file name),
    # *context* (for a compiler context) and *origin* (for the
    # point of origin of chunk emission) can be provided.
    def initialize(@file = "untitled", @context = Context::Compiler.new, @origin = 0)
      @chunks = [Chunk.new(@file, "<unit>")]
    end

    # Given an explanation message, *message*, dies of `CompileError`.
    private def die(message : String)
      # `traces` get deleted after a death; we cannot just
      # have a reference to them.
      traces = @context.traces.dup

      # If the last entry in traces does not point to the
      # entity that had actually caused the death, insert
      # one.
      unless traces.last? == @last.tag
        traces << Trace.new(@last.tag, "<unit>")
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

    # Returns the chunk at *cursor*. Defaults to the chunk-
    # of-emission.
    private macro chunk(at cursor = @target)
      @chunks[{{cursor}}]
    end

    # Introduces a chunk named *name*.
    #
    # In the block, makes the chunk-of-emission be this chunk.
    # The block may receive the target chunk pointer, i.e.,
    # the chunk pointer of this chunk after compilation.
    private macro under(name, &block)
      having @target, be: @chunks.size do
        @chunks << Chunk.new(@file, {{name}})

        {% if block.args %}
          {{*block.args}} = @origin + @target
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

    # Issues a hook call to a function called *name*.
    private macro hook(tag, name, *args)
      visit QCall.new({{tag}}, QRuntimeSymbol.new(QTag.void, {{name}}), {{*args}})
    end

    # Issues the appropriate field gathering instructions
    # for field accessor *accessor*.
    private def field!(accessor : FAImmediate)
      issue(Opcode::FIELD_IMMEDIATE, accessor.access)
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
        issue(Opcode::DUP)  unless index == branches.size -  1

        if branch.is_a?(QAccessField)
          field! [FADynamic.new(branch.head)] + branch.tail
        elsif branch.is_a?(QRuntimeSymbol)
          field! FAImmediate.new(branch.value)
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

    # Emits 'given' appendix values, *givens*, according to
    # *params*.
    #
    # If there are no *givens*, emits `Opcode::ANY` per each
    # param of *params*.
    #
    # On underflow of *givens*, emits the last given until
    # all *params* convered.
    private def given!(params : Array(String), givens : Quotes)
      repeat = false

      params.zip?(givens) do |_, given|
        if !given && !repeat
          issue(Opcode::ANY)
        elsif given.nil?
          visit(givens.last)
        elsif repeat = true
          visit(given)
        end
      end
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

    def visit!(q : QReadtimeSymbol)
      die("readtime symbol caught at compile-time")
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

    def visit!(q : QUPop)
      issue(Opcode::UPOP)
    end

    def visit!(q : QURef)
      issue(Opcode::UREF)
    end

    def visit!(q : QUnary)
      visit(q.operand)

      opcode =
        case q.operator
        when "+" then Opcode::TON
        when "-" then Opcode::NEG
        when "~" then Opcode::TOS
        when "#" then Opcode::LEN
        when "&" then Opcode::TOV
        when "not" then Opcode::TOIB
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
      case target = q.target
      when QSymbol
        visit(q.value)
        @context.bound(target.value) if q.global
        issue(Opcode::TAP_ASSIGN, sym target.value)
      when QCall
        # We'll transform this:
        #   ~> x(0) = 1
        # To this:
        #   ~> __call_assign(x, 1, 0)
        # And this:
        #   ~> x("foo")(0) = 1
        # To this:
        #   ~> __call_assign(x("foo"), 1, 0)
        # Et cetera.
        hook(q.tag, "__call_assign", [target.callee, q.value] + target.args)
      end
    end

    def visit!(q : QBinaryAssign)
      case target = q.target
      when QSymbol
        symbol = sym(target.value)

        visit(q.value)
        issue(Opcode::SYM, symbol)
        issue(Opcode::BINARY_ASSIGN, q.operator)
        issue(Opcode::POP_ASSIGN, symbol)
      when QCall
        # We'll transform this:
        #   ~> x(0) += 1
        # To this:
        #   ~> __call_assign(x, x(0) + 1, 0)
        # And this:
        #   ~> x("foo")(0) += 1
        # To this:
        #   ~> __call_assign(x("foo"), x("foo")(0) + 1, 0)
        # Et cetera.
        hook(q.tag, "__call_assign",
          [target.callee, QBinary.new(q.tag, q.operator, target, q.value)] +
           target.args)
      end
    end

    def visit!(q : QCall)
      visit(q.callee)
      visit(q.args)
      issue(Opcode::CALL, q.args.size)
    end

    def visit!(q : QDies)
      finish = label
      handler = label

      issue(Opcode::SETUP_DIES, handler)
      visit(q.operand)
      issue(Opcode::J, finish)
      label handler
      issue(Opcode::TRUE)
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

    def visit!(q : QAccessField)
      visit(q.head)
      field!(q.tail)
    end

    def visit!(q : QReduceSpread)
      visit(q.operand)
      issue(Opcode::REDUCE, q.operator)
    end

    def visit!(q : QMapSpread)
      start = label
      stop = label

      unless q.iterative
        issue(Opcode::VEC, 0)
      end

      visit(q.operand)
      issue(Opcode::TOV)
      issue(Opcode::MAP_SETUP)
      label start
      issue(Opcode::MAP_ITER, stop)
      issue(Opcode::POP_UPUT)
      visit(q.operator)

      if q.iterative
        issue(Opcode::POP)
      else
        issue(Opcode::MAP_APPEND)
      end

      issue(Opcode::J, start)

      label stop

      unless q.iterative
        issue(Opcode::POP)
      end
    end

    def visit!(q : QIf)
      finish = label
      else_b = label

      visit(q.cond)

      # XXX: This is very much disputed, as it makes things
      # like `|if (_ > 1) _ else 0| [1, 2, 3]` work wrongly.
      #
      issue(Opcode::TAP_UPUT)

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
        under "<block>" do |target|
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
      function = uninitialized VFunction

      name = q.name.value
      givens = q.given
      slurpy = q.slurpy
      params = q.params

      # Parameters affecting the minimum arity.
      #
      aritious = q.params.reject("*")
      arity = aritious.size

      # Issue the function's given appendix.
      #
      given!(params, givens)

      # Functions are bound to the scope of their creation.
      #
      # Generic functions are bound to the scope where the
      # first concrete of that generic was created.
      #
      unless @context.bound?(name)
        @context.bound(name)
      end

      @context.trace(q.tag, name) do
        @context.child do
          under name do |target|
            function = VFunction.new(
              sym(name),   # function's name
              target,      # body chunk
              params,      # params
              params.size, # amount of 'given's (see `given!`)
              arity,       # minimum amount of params
              slurpy,      # slurpiness
            )

            # `Opcode::REST` interprets the slurpie ('*').
            #
            issue(Opcode::REST, arity) if slurpy

            aritious.reverse_each do |param|
              case param
              when "_"
                # Ignore the parameter, but put on the
                # underscores stack.
                #
                issue(Opcode::POP_UPUT)
              else
                # Assign the parameter in the local scope.
                #
                issue(Opcode::POP_ASSIGN, mksym param)
              end
            end

            # Now `return` and `next` will know that they're
            # inside a function, as well as have access to
            # the function's metainfo.
            #
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
      stop  = label

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
      stop  = label

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
      stop  = label

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

    def visit!(q : QBox)
      # Boxes and functions are just too similar to
      # differentiate them under the hood.
      #
      box = uninitialized VFunction

      name = q.name.value
      givens = q.given
      params = q.params
      namespace = q.namespace

      # Again, we first visit the givens.
      #
      given!(params, givens)

      # Much like functions, boxes are bound to the scope of
      # their creation.
      #
      unless @context.bound?(name)
        @context.bound(name)
      end

      @context.child do
        under name do |target|
          box = VFunction.new(
            sym(name),   # boxes' name
            target,      # body chunk
            params,      # params
            params.size, # amount of 'given's (see `given!`)
            params.size, # minimum amount of params
            false,       # slurpiness
          )

          params.reverse_each do |param|
            issue(Opcode::POP_ASSIGN, mksym param)
          end

          # Box namespace is just a bunch of assignments.
          #
          namespace.each do |name, value|
            visit(value)
            issue(Opcode::POP_ASSIGN, mksym name.value)
          end

          issue(Opcode::SYM, sym name)
          issue(Opcode::BOX_INSTANCE)
          issue(Opcode::RET)
        end
      end

      issue(Opcode::BOX, box)
      issue(Opcode::POP_ASSIGN, sym name)
    end

    # Makes a compiler, compiles *quotes* with it and disposes
    # the compiler.
    #
    # *quotes* are the quotes to-be-compiled; *file* is the
    # filename under which they will be compiled; *context*
    # is the compiler context of the compilation.
    #
    # Returns unstitched chunks.
    def self.compile(quotes, file = "untitled", context = Context::Compiler.new, origin = 0)
      compiler = new(file, context, origin)
      compiler.visit(quotes)
      compiler.@chunks
    end
  end
end
