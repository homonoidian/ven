module Ven::Suite
  # An extension to Ven, made in Crystal.
  abstract class Extension
    # Exports the definitions into *context* .
    abstract def load(context : Context::Machine)

    # Declares the definitions in the compiler context.
    abstract def load(context : Context::Compiler)
  end
end
