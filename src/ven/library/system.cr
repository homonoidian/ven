module Ven::Library
  class System < Extension
    on_load do
      # Prints *model* to the screen.
      defbuiltin "say", model : Model do
        # We cannot use `to_str` here, as some models override
        # it to do a bit different thing.
        puts model.is_a?(Str) ? model.value : model

        model
      end

      # Prints *model* to the screen, and then waits for (and
      # consequently returns) user input. If not given one,
      # returns false.
      defbuiltin "ask", model : Model do
        # We cannot use `to_str` here, as some models override
        # it to do a bit different thing.
        print "#{model.is_a?(Str) ? model.value : model} "

        (line = gets) ? line : false
      end

      # Returns the contents of *filename*.
      defbuiltin "slurp", filename : Str do
        File.read(filename.value)
      end

      # **Appends** *content* to *filename*.
      #
      # Creates *filename* if it does not exist.
      defbuiltin "burp", filename : Str, content : Model do
        raw = content.is_a?(Str) ? content.value : content

        File.write(filename.value, raw, mode: "a")
      end

      # **Writes** *content* to *filename*.
      #
      # Creates *filename* if it does not exist.
      defbuiltin "write", filename : Str, content : Model do
        raw = content.is_a?(Str) ? content.value : content

        File.write(filename.value, raw)
      end
    end
  end
end
