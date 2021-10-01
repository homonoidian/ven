require "./*"

module Ven::Suite
  # `Detree` can convert `Quote`s, aka Ven AST, back into runnable
  # Ven source code. Sort of.
  #
  # An important thing to understand is that Ven is highly dependent
  # on its reader. Not having a Reader means missing a lot, and `Detree`
  # does miss a lot; it uglifies at times, and more often than not, just
  # dumps weird code.
  #
  # Also, since `Detree` works on `Quote`s, and there are no readtime
  # constructs at `Quote`-time, beware that you won't see `nud`s, `led`s,
  # readtime holes, etc. in a detree; it's impossible to, and will never
  # be. Instead, you'll see what they expanded into. `distinct` and
  # `exposes` are completely lost, too, but for a different reason
  # (this will be fixed when time comes).
  #
  # Basic usage:
  #
  # ```
  # quotes = Reader.new("1 + 1").read
  #
  # Detree.detree(quotes) # ==> "1 + 1"
  # ```
  class Detree < Visitor(Nil)
    # The amount of spaces in a single indent.
    INDENT_STEP = 2

    # Represents the spacing model.
    #
    # Spacing model is rules that control how, and how many,
    # additional empty lines are inserted between quotes.
    #
    # See `write_spacing` for implementations of these models.
    enum Spacing
      # Do not insert additional empty lines.
      None
      # (Immediate) boxes without blocks get 'glued' together; funs
      # are 'glued' together if they have literal bodies, separated
      # by an empty line if they have the same name, separated by
      # two empty lines otherwise.
      #
      # Everything statementish is separated by two empty lines,
      # non-statementish is 'glued'.
      Toplevel
      # Same as `Toplevel`, but the maximum amount of additional
      # empty lines is one.
      Block
      # All quotes are separated by an empty line.
      EnsureTest
    end

    # Initializes a Detree for the given *io*. The detreed
    # quotes are going to be written to this IO.
    def initialize(@io : IO)
      @indent = 0
    end

    # Returns whether *quote* is a literal quote.
    #
    # Literal quotes are hard-coded. Make sure to update
    # whenever necessary.
    #
    # Quotes that are considered literal:
    #   - `QNumber`
    #   - `QString`
    #   - `QRegex`
    #   - `QSuperlocalTap` (&_)
    #   - `QSuperlocalTake` (_)
    #   - `QRuntimeSymbol`
    #   - `QVector`
    #   - `QMap`
    #   - `QTrue`, `QFalse`
    #
    # Do not confuse with `unamb?`. Unambiguous quotes
    # differ from literal quotes, since some literal
    # quotes are ambiguous (namely `QVector`).
    protected def lit?(quote : MaybeQuote)
      case quote
      when QNumber,
           QString,
           QRegex,
           QSuperlocalTap,
           QSuperlocalTake,
           QRuntimeSymbol,
           QVector,
           QMap,
           QTrue,
           QFalse
        true
      else
        false
      end
    end

    # Returns whether **all* quotes in *quotes* are literal.
    #
    # See `lit?(quote : Quote)`
    protected def lit?(quotes : Quotes)
      quotes.all? { |quote| lit?(quote) }
    end

    # Returns whether *quote* is an unambiguous quote.
    #
    # Unambiguous quotes can be written one after the other
    # without causing semantic/syntactic ambiguity. For example,
    # in `1 2`, `1` is an unambiguous quote, and in `[1] [2]`,
    # there is an ambiguity: `[1][2]` (access) is as valid (from
    # the ambiguity standpoint) as `[1] [2]` (two vectors).
    #
    # Unambiguous quotes are hard-coded. Make sure to update
    # whenever necessary.
    #
    # Quotes that are considered unambiguous:
    #   - `QNumber`
    #   - `QString`
    #   - `QRegex`
    #   - `QTrue`, `QFalse`
    #   - `QSuperlocalTap` (&_)
    #   - `QSuperlocalTake` (_)
    protected def unamb?(quote : MaybeQuote)
      case quote
      when QNumber,
           QString,
           QRegex,
           QTrue,
           QFalse,
           QSuperlocalTap,
           QSuperlocalTake
        true
      else
        false
      end
    end

    # Returns whether **all* quotes in *quotes* are unambiguous.
    #
    # See `unamb?(quote : Quote)`
    protected def unamb?(quotes : Quotes)
      quotes.all? { |quote| unamb?(quote) }
    end

    # Logically joins *items* using a *separator* block.
    # The block is executed for each item. The item is
    # passed to the block if the block expects exactly
    # one argument. The item and the item index is passed
    # to the block if it expects exactly two arguments.
    private macro join(items, separator, &block)
      %items = {{items}}

      %items.each_with_index do |%item, %index|
        {% if block.args.size == 1 %}
          {{*block.args}} = %item
        {% elsif block.args.size == 2 %}
          {{*block.args}} = %item, %index
        {% end %}

        {{yield}}

        unless %index == %items.size - 1
          {{separator}}
        end
      end
    end

    # `join` with *separator* set to ', 's.
    private macro join(items, &block)
      join ({{items}}), separator: begin
        write ","
        write_ws
      end {{ block }}
    end

    # Surrounds *quote* with spacing based on its context, and
    # according to the given *spacing* model.
    #
    # The context is derived from *quotes*, the quotes surrounding
    # *quote* (including *quote* itself), and *index*, the index of
    # *quote* in *quotes*.
    protected def write_spacing(spacing : Spacing, quotes : Quotes, quote : Quote, index : Int32)
      return unless prev = index < 1 ? nil : quotes[index - 1]

      case spacing
      in .none?
        return
      in .toplevel?, .block?
        case {prev, quote}
        when {QBox, QBox}
          # Two consequtive box definitions without blocks get 'glued'
          # together. Otherwise, they are separated by an empty line.
          write_nl unless quote.namespace.empty? && prev.namespace.empty?
        when {QImmediateBox, QImmediateBox}
          # Two consequtive immediate box definitions without blocks
          # get 'glued' together. Otherwise, they are separated by an
          # empty line.
          write_nl unless quote.box.namespace.empty? && prev.box.namespace.empty?
        when {QFun, QFun}
          if lit?(prev.body)
            # Two simple (lit) functions get 'glued' together,
            # even if they have different names.
            #
            #   fun x = 0;
            #   fun y = 1;
            return
          elsif prev.name.value != quote.name.value
            # At toplevel, two functions with different names
            # get separated by two empty lines. Otherwise,
            # by one.
            write_nl unless spacing.block?
          end
          # Two functions with same names & non-literal bodies
          # get separated by one empty line.
          write_nl
        else
          # Everything else gets separated by two newlines, but only
          # if it's statementish. Also, if in block, use only one
          # empty line.
          if prev.stmtish? || quote.stmtish?
            write_nl
            write_nl unless spacing.block?
          end
        end
      in .ensure_test?
        write_nl
      end
    end

    # Joins *quotes* with EOLs (see `write_eol`). *spacing* is the
    # spacing model to use.
    #
    # Writes spacing (see `write_spacing`) **before** each quote
    # of *quotes*.
    protected def statements(spacing : Spacing, quotes : Quotes)
      join quotes.reject &.is_a?(QVoid), separator: write_eol do |quote, index|
        write_spacing spacing, quotes, quote, index
        visit quote
      end
    end

    # Increases indentation by `INDENT_STEP` for the writers
    # in the block. In the block, you are immediately indented
    # and on a new line. After the block, you are immediately
    # dedented and on a new line (unless *dedentln* is set
    # to false).
    protected def indent(dedentln = true)
      @indent += INDENT_STEP
      write_nl
      yield
      @indent -= INDENT_STEP
      write_nl if dedentln
    end

    # Writes the given *object*'s string representation.
    #
    # Identical to `io << object`.
    protected def write(object)
      @io << object
    end

    # Writes *n* whitespace characters.
    protected def write_ws(n = 1)
      write " " * n
    end

    # Writes the whitespace characters required to fulfill
    # the current indentation level.
    protected def write_indent
      write_ws @indent
    end

    # Writes a newline followed by indent (see `write_indent`).
    protected def write_nl
      write "\n"
      write_indent
    end

    # Writes a semicolon followed by newline (see `write_nl`).
    protected def write_eol
      write ";"
      write_nl
    end

    # Writes *opener* before the block, and the corresponding
    # close character after.
    #
    # Currently supported openers are: "(", "[", "{".
    protected def surround(opener : String)
      case opener
      when "("
        write "("
        yield
        write ")"
      when "["
        write "["
        yield
        write "]"
      when "{"
        write "{"
        yield
        write "}"
      else
        raise "bad opener"
      end
    end

    # Surrounds the block with parentheses.
    #
    # For example, `in_parens { write "1" }` writes `(1)`.
    protected def in_parens
      surround "(" { yield }
    end

    # Surrounds the result of visiting *quote* in parentheses.
    protected def in_parens(quote : Quote)
      in_parens { visit quote }
    end

    # Writes an operand of an expression of some kind.
    #
    # The general rule is the following. If *operand* is a `QBinary`
    # with operator equal to *operator*, it's written untouched. If
    # *operand* is a `QBinary` with operator not equal to *operator*,
    # it's written enclosed in parentheses. Otherwise, *operand* is
    # also written untouched.
    #
    # For cases like `2 + 2 + 2`, or `2 * 2 * 6`, we clearly don't
    # need parentheses. For cases like `2 + 2 * 2`, it's impossible to
    # know whether we need parentheses: there is just no way to figure
    # out operator precedence without a reader instance, and there is,
    # of course, no reader instance anymore at Detree-time. In these
    # kinds of cases, it is just safer to use parentheses.
    #
    # Be careful not to confuse this method (with operator empty in
    # particular) with `write_disamb`. This method will surround
    # *operand* with parens only if it is a binary operation.
    protected def write_operand(operand : QBinary, operator = "")
      operator == operand.operator ? visit operand : in_parens operand
    end

    # If *operand*'s operator is equal to *operator*, wraps *operand*
    # in parentheses & visits it. Otherwise, just visits *operand*.
    #
    # This method is useful for expressions such as `+(+x)`, which,
    # if not for this method, would be detreed into `++x` (a syntax
    # error in Ven).
    #
    # Be careful not to confuse this method with `write_disamb`.
    # This method **will not** surround *operand* with parens
    # if operator is empty (which it is by default). This might
    # lead to ambiguities along the way.
    protected def write_operand(operand : QUnary, operator = "")
      operator == operand.operator ? in_parens operand : visit operand
    end

    # Always wraps *operand* in parentheses. Raw assignments
    # cannot be operands, this is a syntax error. We have to
    # wrap them in parentheses.
    #
    # See, for example,
    #
    # ```ven
    # # This dies (since 'x < y' is not a valid assignment
    # # target):
    # ensure x < y = compute-y();
    #
    # # And this works:
    # ensure x < (y = compute-y());
    # ```
    protected def write_operand(operand : QAssign | QBinaryAssign, operator = "")
      in_parens operand
    end

    # Same as `visit operand`.
    protected def write_operand(operand, operator = "")
      visit operand
    end

    # Disambiguates & writes *quote*. If *quote* is an
    # ambiguous quote, wraps it in parentheses, otherwise
    # writes it as-is.
    protected def write_disamb(quote : Quote)
      unamb?(quote) ? visit quote : in_parens quote
    end

    # Writes *quote* if it is literal (see `lit?`), otherwise
    # wraps it in parentheses and then writes.
    protected def write_lit(quote : Quote)
      lit?(quote) ? visit quote : in_parens quote
    end

    # Writes a comma-separated list of visited *items*. The
    # trailing comma is omitted. One whitespace character is
    # inserted after each comma.
    protected def write_list(quotes : Quotes)
      join(quotes) { |quote| visit quote }
    end

    # Writes a comma-separated list of *names*. The trailing
    # comma is omitted. One whitespace character is inserted
    # after each comma.
    protected def write_list(names : Array(String))
      join(names) { |name| write name }
    end

    # Wraps *quotes* in a block.
    #
    # If the block has exactly one literal item, and *multiline*
    # is set to false, writes the following:
    #
    # ```ven
    # { <> }
    # ```
    #
    # Otherwise, writes the following:
    #
    # ```ven
    # {
    #   <>;
    #   <>;
    #   ...
    # }
    # ```
    protected def write_block(quotes : Quotes, multiline = false)
      surround "{" do
        if !multiline && quotes.size == 1 && lit?(quotes.first)
          write_ws
          visit quotes
          write_ws
        else
          # Statements and statement-likes are always on a
          # new line and indented, even if the block body
          # is one item long:
          indent { statements Spacing::Block, quotes }
        end
      end
    end

    # See `write_block(quote)`.
    protected def write_block(block : QBlock, *args, **kwargs)
      write_block(block.body, *args, **kwargs)
    end

    # Writes the source part of function *param*eter*s*
    # (see `Parameters`).
    protected def write_params(params : Parameters)
      in_parens do
        join params do |param|
          visit param.source
        end
      end
    end

    # Writes the `given` part of function *param*eter*s*.
    #
    # See `Parameters`.
    protected def write_given(params : Parameters)
      write_ws
      write "given"
      write_ws
      join params do |param|
        # If there are some givens, all givens are be non-nil
        # (that's how the language works)
        visit param.given.not_nil!
      end
    end

    # Writes *items* as vector items.
    #
    # Uses the space-separated syntax supported by some core
    # language structures, for example, maps and vectors. Do
    # note that only *items* that fully consist of unambiguous
    # quotes get written this way. Mixed, and ambiguous *items*
    # are separated with ', 's as expected.
    protected def write_items(items : Quotes)
      return write_list items unless unamb?(items)

      join items, separator: write_ws do |item|
        visit item
      end
    end

    # Writes a loop *rep*eatee (body).
    #
    # Note that this method must be in control of whether to
    # put whitespace/newline before *rep*.
    protected def write_rep(rep : QBlock)
      write_ws
      write_block rep
    end

    # :ditto:
    protected def write_rep(rep : Quote)
      if lit?(rep)
        write_ws
        visit rep
      else
        indent dedentln: false { visit rep }
      end
    end

    # Returns the arms of an *if quote*. Recurses on *quote*'s
    # alt: returns nested if-elses flattened. This is useful to
    # extract the ifs nested in alt (aka 'else if's).
    #
    # Returns an array of tuples where the first element is
    # the condition of the arm (or nil if it's the else arm),
    # and the second element is the body of the arm.
    protected def arms_of(if quote : QIf) : Array({MaybeQuote, Quote})
      [{quote.cond, quote.suc}] + arms_of(quote.alt)
    end

    # :ditto:
    protected def arms_of(if quote : Quote) : Array({MaybeQuote, Quote})
      [{nil, quote}] of {MaybeQuote, Quote}
    end

    # :ditto:
    protected def arms_of(if quote : Nil) : Array({MaybeQuote, Quote})
      [] of {MaybeQuote, Quote}
    end

    def visit!(q : QVoid)
      # QVoids are mostly leftovers from readtime. We can
      # safely ignore them.
    end

    def visit!(q : QQuoteEnvelope)
      visit q.quote
    end

    def visit!(q : QNumber | QRuntimeSymbol)
      write q.value
    end

    def visit!(q : QString)
      # ESCAPES are ESCAPED => UNESCAPED initially, but
      # we want it to be UNESCAPED => ESCAPED.
      escapes = Parselet::PString::ESCAPES.invert

      write '"'
      write q.value.gsub { |ch| escapes[ch.to_s]? || ch }
      write '"'
    end

    def visit!(q : QRegex)
      write "`"
      write q.value
      write "`"
    end

    def visit!(q : QVector)
      surround "[" { write_items q.items }
    end

    def visit!(q : QFilterOver)
      subject = q.subject

      surround "[" do
        if subject.is_a?(QVector)
          # Splice items if subject is a vector.
          write_items subject.items
        else
          # Otherwise paste raw. Shouldn't cause any ambiguities,
          # since there's no trailing comma & '|' is powerful.
          visit subject
        end
        write_ws
        write "|"
        write_ws
        visit q.filter
      end
    end

    def visit!(q : QMap)
      write "%{"

      unless q.keys.empty?
        # We don't have to check if keys are unamb since
        # (a) the syntax proves they are, and (2) because
        # of the QRuntimeSymbol/QString check below.
        spaces = unamb?(q.vals)

        write_ws

        join q.keys.zip(q.vals), separator: begin
          write "," unless spaces
          write_ws
        end do |(key, val)|
          # Only symbol/string keys are allowed in maps (and symbol
          # keys are normalized to strings). Other kinds of keys
          # have to be surrounded with parentheses.
          if key.is_a?(QRuntimeSymbol) || key.is_a?(QString)
            visit key
          else
            in_parens key
          end

          write_ws
          visit val
        end

        write_ws
      end

      write "}"
    end

    def visit!(q : QTrue)
      write "true"
    end

    def visit!(q : QFalse)
      write "false"
    end

    def visit!(q : QSuperlocalTake)
      write "_"
    end

    def visit!(q : QSuperlocalTap)
      write "&_"
    end

    def visit!(q : QUnary)
      write q.operator
      # If all characters in the operator are ASCII alphanumeric
      # (all Ven keywords are), put a space (otherwise, it will
      # collide with the operand).
      if q.operator.chars.all?(&.ascii_alphanumeric?)
        write_ws
      end
      write_lit q.operand
    end

    def visit!(q : QBinary)
      write_operand q.left, q.operator
      write_ws
      write q.operator
      write_ws
      write_operand q.right, q.operator
    end

    def visit!(q : QCall)
      write_operand q.callee
      in_parens { write_list q.args }
    end

    def visit!(q : QAssign)
      visit q.target
      write_ws
      write (q.global ? ":=" : "=")
      write_ws
      visit q.value
    end

    def visit!(q : QBinaryAssign)
      visit q.target
      write_ws
      write q.operator
      write "="
      write_ws
      visit q.value
    end

    def visit!(q : QDies)
      write_lit q.operand
      write_ws
      write "dies"
    end

    def visit!(q : QIntoBool)
      # `name?` clashes with (name)?
      #
      # Make sure to parenthesize symbols here.
      if q.operand.is_a?(QRuntimeSymbol)
        in_parens q.operand
      else
        write_lit q.operand
      end
      write "?"
    end

    def visit!(q : QReturnDecrement)
      write_operand q.target
      write "--"
    end

    def visit!(q : QReturnIncrement)
      write_operand q.target
      write "++"
    end

    def visit!(q : QAccess)
      write_operand q.head
      surround "[" do
        write_list q.args
      end
    end

    def visit!(q : QAccessField)
      write_operand q.head

      # QAccessField with empty tail (no field accesses)
      # is impossible.
      write "."

      # Tail is a bunch of field accessors. Field accessors
      # are mostly normal expressions, not much weirdness is
      # needed to write them.
      join q.tail, separator: (write ".") do |accessor|
        case accessor
        when FAImmediate, FABranches
          # FAImmediate's access is a QSymbol (perfectly visitable),
          # and FABranche's is a QVector (too).
          visit accessor.access
        when FADynamic
          in_parens accessor.access
        end
      end
    end

    def visit!(q : QMapSpread)
      write "|"
      visit q.operator
      write "|"
      write ":" if q.iterative
      write_ws
      visit q.operand
    end

    def visit!(q : QReduceSpread)
      write "|"
      write q.operator
      write "|"
      write_ws
      visit q.operand
    end

    def visit!(q : QBlock)
      write_block q
    end

    def visit!(q : QGroup)
      statements Spacing::Block, q.body
    end

    def visit!(q : QIf)
      # Write the simplest ifs without collecting their arms.
      #
      # We consider an if with a literal success arm, and no
      # alternative arm or a literal alternative arm, simple.
      #
      #   if 1 2
      #   if 1 2 else 3
      #
      # These are written as shown.
      if lit?(q.suc) && (!q.alt || lit? q.alt)
        write "if"
        write_ws
        write_disamb q.cond
        write_ws
        write_disamb q.suc
        write_ws
        if alt = q.alt
          write "else"
          write_ws
          write_disamb alt
        end
        return
      end

      # Otherwise, collect (flatten) the arms.
      arms = arms_of(q)
      arms.each_with_index do |(cond, body), index|
        prev = index > 0 ? arms[index - 1] : nil

        if prev.is_a?(QBlock)
          write_ws
          write "else"
          write_ws
        elsif prev
          write_nl
          write "else"
          write_ws
        end

        if cond
          write "if"
          write_ws
          write_disamb cond
        end

        if body.is_a?(QBlock)
          write_ws
          write_block body, multiline: true
        else
          # Use the indented form if the body is not a block:
          #
          #   if x > 5
          #     say("Hello!")
          #   else if x < 4
          #     "Bye!"
          #
          # (even if it is literal, as shown!)
          indent dedentln: false { visit body }
        end
      end
    end

    def visit!(q : QFun)
      body, params = q.body, q.params

      write "fun"
      write_ws
      visit q.name

      unless params.empty?
        write_params params
        write_given params if params.givens.all?
      end

      write_ws

      if body.size == 1 && !body.first.stmtish?
        write "="
        if lit?(body)
          # Literal bodies get written like this:
          #   fun x = 1
          write_ws
          visit body
        else
          # Non-literal, non-stmtish bodies get written
          # using the indented style:
          #   fun x =
          #     say("Hello World!")
          indent dedentln: false { visit body }
        end
      else
        # Otherwise, the blocky syntax is used:
        #
        #   fun x {
        #     ...
        #   }
        write_block body
      end
    end

    def visit!(q : QQueue)
      write "queue"
      write_ws
      visit q.value
    end

    def visit!(q : QInfiniteLoop)
      write "loop"
      write_rep q.repeatee
    end

    def visit!(q : QBaseLoop)
      write "loop"
      write_ws
      write_operand q.base
      write_rep q.repeatee
    end

    def visit!(q : QStepLoop)
      write "loop"
      write_ws
      in_parens do
        visit q.base
        write ","
        write_ws
        visit q.step
      end
      write_rep q.repeatee
    end

    def visit!(q : QComplexLoop)
      write "loop"
      write_ws
      in_parens do
        visit q.start
        write ","
        write_ws
        visit q.base
        write ","
        write_ws
        visit q.step
        write_ws
      end
      write_rep q.repeatee
    end

    def visit!(q : QNext)
      write "next"
      if scope = q.scope
        write_ws
        write scope
      end
      unless q.args.empty?
        write_ws
        write_list q.args
      end
    end

    def visit!(q : QReturnQueue)
      write "return"
      write_ws
      write "queue"
    end

    def visit!(q : QReturnStatement)
      write "return"
      write_ws
      visit q.value
    end

    def visit!(q : QReturnExpression)
      in_parens do
        write "return"
        write_ws
        visit q.value
      end
    end

    def visit!(q : QBox)
      write "box"
      write_ws
      visit q.name
      unless q.params.empty?
        write_params q.params
        write_given q.params if q.params.givens.all?
      end
      unless q.namespace.empty?
        write_ws
        surround "{" do
          indent do
            join q.namespace, separator: write_eol do |(name, quote)|
              visit name
              write_ws
              write "="
              write_ws
              visit quote
            end
          end
        end
      end
    end

    def visit!(q : QLambda)
      in_parens { write_list q.params }
      write_ws
      visit q.body
    end

    def visit!(q : QEnsure)
      write "ensure"
      write_ws
      visit q.expression
    end

    def visit!(q : QEnsureTest)
      write "ensure"
      write_ws
      visit q.comment
      write_ws
      surround "{" do
        indent do
          statements Spacing::EnsureTest, q.shoulds
        end
      end
    end

    def visit!(q : QEnsureShould)
      write "should"
      write_ws
      write '"'
      write q.section
      write '"'
      write_ws
      indent dedentln: false { statements Spacing::None, q.pad }
    end

    def visit!(q : QPatternEnvelope)
      write "'"
      visit q.pattern
    end

    def visit!(q : QImmediateBox)
      write "immediate"
      write_ws
      visit q.box
    end

    # Visits *subject* in the toplevel context.
    def toplevel(subject : Quote)
      visit(subject)
    end

    # :ditto:
    def toplevel(subject : Quotes)
      statements(Spacing::Toplevel, subject)
    end

    # Detrees *subject* into *io*.
    def self.detree(subject : Quote | Quotes, io : IO)
      new(io).toplevel(subject)
    end

    # Detress *subject* into a string, and returns the string.
    def self.detree(subject : Quote | Quotes)
      String.build do |io|
        detree(subject, io)
      end
    end
  end
end
