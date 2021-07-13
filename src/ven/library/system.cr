module Ven::Library
  class System < Extension
    on_load do
      fancy = Fancyline.new

      # Prints *model* to `STDOUT`.
      defbuiltin "say", model : Model do
        # We cannot use `to_str` here, as some models override
        # it to do a bit different thing.
        puts model.is_a?(Str) ? model.value : model

        model
      end

      # Prompts *model* followed by a space, and waits for user
      # input (which it consequently returns). If got EOF, dies
      # with `"end-of-input"`. If got CTRL+C, dies with
      # `"interrupted"`.
      defbuiltin "ask", model : Model do
        prompt = "#{model.is_a?(Str) ? model.value : model} "

        # I hate to use fancyline here (it's too heavyweight,
        # plus the overflow problem!), but with `gets` you
        # can't die of CTRL+C properly, and we want 'ask' to
        # die of CTRL+C properly.
        fancy.readline(prompt, history: false) || machine.die("end-of-input")
      rescue Fancyline::Interrupt
        machine.die("interrupted")
      end

      # Returns the content of *filename*.
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
