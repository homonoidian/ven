module Ven
  # Peephole optimizer for Ven unstitched chunks.
  #
  # Matches sequences of bytecode instructions against patterns,
  # and, based on that, folds, removes or modifies them.
  #
  # ```
  # puts Optimizer.optimize(unstitched_chunks) # => stitched chunks
  # ```
  class Optimizer
    include Suite

    # Returns the chunks of this optimizer.
    getter chunks : Chunks

    # The amount of optimization passes to do.
    property passes = 8

    # Makes an Optimizer from *chunks*, an array of
    # unstitched chunks.
    def initialize(@chunks : Chunks)
    end

    # Returns the argument of *instruction*.
    #
    # Ensures the argument is not nil.
    private macro argument(of instruction)
      {{instruction}}.argument.not_nil!
    end

    # Assumes *source* is a `VStatic`; returns the value of
    # this `VStatic` if it is of the given *type*, raises
    # otherwise.
    #
    # **Expects *chunk* to be in the scope.**
    private macro static(of source, as type)
      chunk.resolve({{source}}).as(VStatic).value.as({{type}})
    end

    # A shorthand for `Chunk#offset`.
    #
    # **Expects *chunk* to be in the scope.**
    private macro offset(for value)
      chunk.offset({{value}})
    end

    # If possible, applies the given binary *operator* on known
    # `BigDecimal`s *left* and *right*. Otherwise, returns nil.
    def binary(operator : String, left : BigDecimal, right : BigDecimal)
      # Let the fail happen at runtime (as we cannot die in
      # the optimizer).
      return if right == 0

      case operator
      when "+"
        left + right
      when "-"
        left - right
      when "*"
        left * right
      when "/"
        left / right
      end
    end

    # If possible, applies the given binary *operator* on known
    # `String`s *left* and *right*. Otherwise, returns nil.
    def binary(operator : String, left : String, right : String)
      case operator
      when "~"
        left + right
      end
    end

    # Goes over *chunk*'s snippets, performing exactly one
    # optimization first for threes, and then for twos of
    # instructions in each snippet.
    #
    # This method performs **peephole optimization**. It finds
    # blobs of redundant or readily computable instructions,
    # and eliminates or computes them.
    def optimize(chunk : Chunk)
      chunk.snippets.each do |snippet|
        # Optimize top-to-bottom first for threes (triplets)
        snippet.for(3) do |(left, right, operator), start|
          case {left.opcode, right.opcode, operator.opcode}
          when {Opcode::NUM, Opcode::NUM, Opcode::BINARY}
            resolution = binary(
              static(of: operator, as: String),
              static(of: left, as: BigDecimal),
              static(of: right, as: BigDecimal))

            if resolution
              break snippet.replace(start, 3, Opcode::NUM, offset for: resolution)
            end
          when {Opcode::STR, Opcode::STR, Opcode::BINARY}
            resolution =
              binary(
                static(of: operator, as: String),
                static(of: left, as: String),
                static(of: right, as: String))

            if resolution
              break snippet.replace(start, 3, Opcode::STR, offset for: resolution)
            end
          when {Opcode::BINARY, Opcode::STR, Opcode::BINARY}
            # A special-case optimization to avoid creating
            # an empty string when stitching:
            #   ~> "a" ~ "b" ~ ""
            # Gets optimized to:
            #   ==> "a" ~ "b"
            # But:
            #   ~> "a" ~ ""
            # Does not:
            #   ==> "a" ~ ""
            # This is useful when working with interpolation:
            #   ~> "hello$world"
            # => "hello" ~ world ~ ""
            #   ==> "hello" ~ world
            if static(of: left, as: String) == "~" &&
               static(of: right, as: String) == "" &&
               static(of: operator, as: String) == "~"
              break snippet.remove(start, 2)
            end
          end
        end

        # ... and then for twos (duplets) of instructions.
        snippet.for(2) do |(head, tail), start|
          case {head.opcode, tail.opcode}
          when {Opcode::NUM, Opcode::TON}
            break snippet.replace(start, 2, Opcode::NUM, argument of: head)
          when {Opcode::STR, Opcode::TOS}
            break snippet.replace(start, 2, Opcode::STR, argument of: head)
          when {Opcode::VEC, Opcode::TOV}
            break snippet.replace(start, 2, Opcode::VEC, argument of: head)
          when {Opcode::TAP_ASSIGN, Opcode::POP}
            break snippet.replace(start, 2, Opcode::POP_ASSIGN, argument of: head)
          when {Opcode::POP_SFILL, Opcode::STAKE}
            break snippet.remove(start, 2)
          when {Opcode::TAP_SFILL, Opcode::POP}
            break snippet.replace(start, 2, Opcode::POP_SFILL, argument of: head)
          when {Opcode::TAP_SFILL, Opcode::IF_SFILL}
            # Forced if superlocal fill:
            #   ~> if ^true say("Hi!")
            #
            # ... doesn't need double/if-sfilling. Get rid of the IF_SFILL.
            break snippet.remove(start + 1, 1)
          when {Opcode::INC, Opcode::POP}
            break snippet.replace(start, 2, Opcode::FAST_INC, argument of: head)
          when {Opcode::DEC, Opcode::POP}
            break snippet.replace(start, 2, Opcode::FAST_DEC, argument of: head)
          when {Opcode::J, _}
            # There are only cross-snippet jumps. In one snippet
            # therefore, everything past an absolute jump is
            # not accessible.
            break snippet.replace(start, 2, Opcode::J, head.label)
          when {.puts_one?, Opcode::POP}
            # First instruction of the pair produces one value,
            # and second pops it right away.
            break snippet.remove(start, 2)
          end
        end
      end
    end

    # Optimizes the chunks of this Optimizer in several *passes*.
    def optimize
      @passes.times do
        @chunks.each do |chunk|
          optimize(chunk)
        end
      end
    end
  end
end
