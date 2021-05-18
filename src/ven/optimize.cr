module Ven
  # Peephole optimizer for Ven unstitched chunks.
  #
  # Matches sequences of bytecode instructions against patterns,
  # and, based on that, folds, removes or modifies them.
  #
  # Basic usage:
  # ```
  # puts Optimizer.optimize(unstitched_chunks) # => stitched chunks
  # ```
  class Optimizer
    include Suite

    # Makes an Optimizer from *chunks*, an array of
    # unstitched chunks.
    def initialize(@chunks : Chunks)
    end

    # Returns *instruction*'s argument.
    #
    # Ensures the argument is not nil.
    private macro argument(instruction)
      {{instruction}}.argument.not_nil!
    end

    # Assumes *source* is a static payload carrying a value
    # of type *type*.
    #
    # **Assumes that a variable named *chunk* is in the scope.**
    private macro static_as(source, type)
      chunk.resolve({{source}}).as(VStatic).value.as({{type}})
    end

    # Returns the data offset of *value*.
    #
    # **Assumes that a variable named *chunk* is in the scope.**
    private macro to_offset(value)
      chunk.offset({{value}})
    end

    # Computes, if possible, a binary operator, *operator*,
    # with *left* and *right* being known BigDecimals (thus
    # nums in Ven).
    #
    # Returns nil if haven't optimized.
    def binary2n(operator : String, left : BigDecimal, right : BigDecimal)
      # Let the fail happen at runtime (because we have no
      # way to err in the optimizer).
      #
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

    # Computes, if possible, a binary operator, *operator*,
    # with *left* and *right* being known Strings (thus strs
    # in Ven).
    #
    # Returns nil if haven't optimized.
    def binary2s(operator : String, left : String, right : String)
      case operator
      when "~"
        left + right
      end
    end

    # Goes over *chunk*'s snippets, performing exactly one
    # optimization first for threes, and then for twos of
    # instructions in each snippet.
    #
    # This method performs what's known as **peephole optimization**.
    # It finds blobs of redundant or readily computable instructions,
    # and eliminates them in various ways.
    def optimize(chunk : Chunk)
      chunk.snippets.each do |snippet|
        snippet.for(3) do |triplet, start|
          case triplet.map(&.opcode)
          when [Opcode::NUM, Opcode::NUM, Opcode::BINARY]
            resolution =
              binary2n(
                static_as(triplet[2], String),
                static_as(triplet[0], BigDecimal),
                static_as(triplet[1], BigDecimal))

            if resolution
              break snippet.replace(start, 3, Opcode::NUM, to_offset resolution)
            end
          when [Opcode::STR, Opcode::STR, Opcode::BINARY]
            resolution =
              binary2s(
                static_as(triplet[2], String),
                static_as(triplet[0], String),
                static_as(triplet[1], String))

            if resolution
              break snippet.replace(start, 3, Opcode::STR, to_offset resolution)
            end
          when [Opcode::BINARY, Opcode::STR, Opcode::BINARY]
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
            #   => "hello" ~ world ~ ""
            #   ==> "hello" ~ world
            if static_as(triplet[0], String) == "~"   &&
                 static_as(triplet[1], String) == ""  &&
                 static_as(triplet[2], String) == "~"
              break snippet.remove(start, 2)
            end
          end
        end

        snippet.for(2) do |pair, start|
          case pair.map(&.opcode)
          when [Opcode::NUM, Opcode::TON]
            break snippet.replace(start, 2, Opcode::NUM, argument pair[0])
          when [Opcode::STR, Opcode::TOS]
            break snippet.replace(start, 2, Opcode::STR, argument pair[0])
          when [Opcode::VEC, Opcode::TOV]
            break snippet.replace(start, 2, Opcode::VEC, argument pair[0])
          when [Opcode::TAP_ASSIGN, Opcode::POP]
            break snippet.replace(start, 2, Opcode::POP_ASSIGN, argument pair[0])
          when [Opcode::POP_UPUT, Opcode::UPOP]
            break snippet.remove(start, 2)
          end

          if pair.first.opcode == Opcode::J
            # At this point we are in the snippet-world, so
            # there are only cross-snippet jumps. In one snippet
            # therefore, everything past an absolute jump is
            # dead code.
            #
            break snippet.replace(start, 2, Opcode::J, pair.first.label)
          elsif pair.first.opcode.puts_one? && pair[1].opcode == Opcode::POP
            # First instruction of the pair produces one value,
            # and second pops it right away.
            #
            break snippet.remove(start, 2)
          end
        end
      end
    end

    # Optimizes the chunks of this Optimizer in several *passes*.
    def optimize(passes)
      passes.times do
        @chunks.each do |chunk|
          optimize(chunk)
        end
      end
    end

    # Given an array of unstitched chunks, *chunks*, optimizes
    # them in *passes* passes. Stitches the optimized chunks
    # and returns them.
    def self.optimize(chunks, passes = 1)
      new(chunks).optimize(passes)
      chunks.map(&.complete!)
    end
  end
end
