module Ven::Library
  class System < Extension
    def load(c_context, m_context)
      # Prints *model* to the screen.
      defbuiltin "say", model : Model do
        puts model.to_str.value
        model
      end

      # Prints *model* to the screen, and then waits for (and
      # consequently returns) user input. Unless given one,
      # returns false.
      defbuiltin "ask", model : Model do
        print "#{model.to_str.value} "
        (line = gets) ? line : false
      end
    end
  end
end
