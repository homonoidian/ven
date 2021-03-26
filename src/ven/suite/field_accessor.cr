module Ven::Suite
  # A field accessor is an individual piece of a field path.
  #
  # For example, in `a.b.c` `a` is the head, and `b.c` is the
  # field path. And, in `b.c`, `b` is the first field accessor
  # and `c` is the second.
  abstract struct FieldAccessor
    macro takes(type)
      getter access : {{type}}

      def initialize(@access)
      end
    end
  end

  # An immediate field accessor.
  #
  # In the field path `b.c`, both `b` and `c` are immediate
  # field accessors.
  struct FAImmediate < FieldAccessor
    takes String
  end

  # A dynamic field accessor.
  #
  # In the field path `("field" ~ 1).b`, `("field" ~ 1)` is a
  # dynamic field accesor.
  struct FADynamic < FieldAccessor
    takes Quote
  end

  # A multifield accessor.
  #
  # In the field path `(a).[b.e, c]`, `[b.e, c]` is a multifield
  # accessor.
  struct FAMulti < FieldAccessor
    takes QVector
  end

  alias FieldAccessors = Array(FieldAccessor)
end
