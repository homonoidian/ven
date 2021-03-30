module Ven
  class Optimizer
    include Suite

    def initialize(@chunks : Chunks)
    end

    # Returns the *instruction*'s argument, ensuring it is
    # not nil.
    private macro argument(instruction)
      {{instruction}}.argument.not_nil!
    end

    # Assumes *source* is a static payload carrying *type*.
    #
    # ** *chunk* (variable) must be in the scope prior to
    # a call to this.**
    private macro static(source, type)
      chunk.resolve({{source}}).as(VStatic).value.as({{type}})
    end

    # Computes the offset of *value*.
    #
    # ** *chunk* (variable) must be in the scope prior to
    # a call to this.**
    private macro offsetize(value)
      chunk.offset({{value}})
    end

    # Computes, if possible, an *operator* with *left*, *right*
    # being known BigDecimals (in Ven, nums).
    def binary2n(operator : String, left : BigDecimal, right : BigDecimal)
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

    # Computes, if possible, an *operator* with *left*, *right*
    # being known Strings (in Ven, strs).
    def binary2s(operator : String, left : String, right : String)
      case operator
      when "~"
        left + right
      end
    end

    # Optimizes every one of the *chunk*'s snippets once.
    #
    # This method performs what's known as **peephole optimization**.
    # It finds blobs of redundant or readily computable instructions,
    # and gets rid of them in various ways.
    #
    # Note that certain optimizations may require multiple
    # `optimize` passes. E.g., it is impossible to compute
    # `2 + 2 + 2` in 1 pass (2 passes are required).
    def optimize(chunk : Chunk)
      chunk.snippets.each do |snippet|
        snippet.for(3) do |triplet, start|
          case triplet.map(&.opcode)
          when [Opcode::NUM, Opcode::NUM, Opcode::BINARY]
            resolution =
              binary2n(
                static(triplet[2], String),
                static(triplet[0], BigDecimal),
                static(triplet[1], BigDecimal))

            if resolution
              break snippet.replace(start, 3, Opcode::NUM, offsetize resolution)
            end
          when [Opcode::STR, Opcode::STR, Opcode::BINARY]
            resolution =
              binary2s(
                static(triplet[2], String),
                static(triplet[0], String),
                static(triplet[1], String))

            if resolution
              break snippet.replace(start, 3, Opcode::STR, offsetize resolution)
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
            # At this point we are in the snippet-world and
            # there are only cross-snippet jumps. In one snippet
            # therefore, everything past an absolute jump is
            # dead weight.
            break snippet.replace(start, 2, Opcode::J, pair.first.label)
          elsif pair.first.opcode.puts_one? && pair[1].opcode == Opcode::POP
            # First instruction of the pair produces one value,
            # and second pops it right away. No effect at all.
            break snippet.remove(start, 2)
          end
        end
      end
    end

    # Optimizes the chunks of this Optimizer in several *passes*.
    def optimize(passes = 1)
      passes.times do
        @chunks.each do |chunk|
          optimize(chunk)
        end
      end
    end
  end
end
