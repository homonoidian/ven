module Ven::Suite
  # A field accessor is an individual piece of a field path.
  #
  # For example, in `a.b.c` `a` is the head, and `b.c` is the
  # field path. And, in `b.c`, `b` is the first field accessor
  # and `c` is the second.
  abstract struct FieldAccessor
    include JSON::Serializable

    macro finished
      # This (supposedly) makes it possible to reconstruct
      # a FieldAccessor from JSON.
      use_json_discriminator("__access_type", {
        {% for subclass in @type.subclasses %}
          {{subclass.name.split("::").last}} => {{subclass}},
        {% end %}
      })
    end

    macro inherited
      # An internal instance variable used to determine which
      # type of field accessor should a FieldAccessor be
      # deserialized into.
      @__access_type = {{@type.name.split("::").last}}
    end

    macro takes(type)
      # Returns the access quote.
      getter access : {{type}}

      def initialize(@access)
        # Same as in `Quote`, same as in `Parameter`: there
        # must be no QGroup in Quote's place.
        if @access.is_a?(QGroup)
          raise ReadError.new(@access.tag, "got group where expression expected")
        end
      end

      def to_s(io)
        io << @access
      end
    end
  end

  # An immediate field accessor.
  #
  # In the field path `b.c`, both `b` and `c` are immediate
  # field accessors.
  struct FAImmediate < FieldAccessor
    takes QSymbol

    # Makes a copy of this field accessor.
    def clone
      self
    end
  end

  # A dynamic field accessor.
  #
  # In the field path `("field" ~ 1).b`, `("field" ~ 1)` is a
  # dynamic field accesor.
  struct FADynamic < FieldAccessor
    takes Quote

    # Makes a deep copy of this field accessor.
    def clone
      FADynamic.new(@access.clone)
    end
  end

  # A branches field accessor.
  #
  # In the field path `(a).[b.e, c]`, `[b.e, c]` is a branches
  # field accessor.
  struct FABranches < FieldAccessor
    takes QVector

    # Makes a deep copy of this field accessor.
    def clone
      FABranches.new(@access.clone)
    end
  end

  alias FieldAccessors = Array(FieldAccessor)
end
