module Ven::Suite::Readtime
  alias Definitions = Hash(String, Quote)

  # The state of a readtime envelope.
  #
  # Each given readtime envelope has its own state with a number
  # of accessibles: definitions, which are the variables of readtime
  # Ven, the superlocal value, the queue, and the return value.
  class State
    # Returns the readtime symbol definitions.
    getter definitions : Definitions
    # Returns the superlocal of this state.
    getter superlocal : Superlocal(Quote)

    # The queue of quotes. Queue overrides expression-return
    # & implicit last quote return, and makes the envelope
    # expand into a QBlock of quotes in the queue.
    property queue = Quotes.new
    # The value set by an expression return.
    property return : MaybeQuote = nil

    def initialize(@definitions, @superlocal = Superlocal(Quote).new)
    end

    # Returns a new `State`, with its `definitions` being
    # this state's definitions merged with *override*, and
    # its `superlocal` this state's superlocal if *borrow*
    # is true.
    #
    # Keeps other properties intact.
    def with(override = Definitions.new, borrow = false)
      merged = @definitions.merge(override)
      child = borrow ? State.new(merged, @superlocal) : State.new(merged)
      # Child's return & queue expressions reference the
      # parent's return & queue expressions. Writes are
      # redirected to the parent state!
      child.queue = @queue
      child.return = @return
      child
    end

    # Returns a new `State`, with its `superlocal` filled
    # with *value*. The superlocal values prior to *value*
    # are borrowed if *borrow* is true.
    #
    # Keeps other properties intact.
    def with(value : Quote, borrow = false)
      child = self.with(borrow: borrow)
      child.superlocal.fill(value)
      child
    end
  end
end
