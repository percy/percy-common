# A struct that only allows keyword arguments.
# For example, this should be used to create value objects that are returned from service methods,
# instead of just returning a hash.
#
# Usage:
#   class Foo < Percy::KeywordStruct.new(:bar, :baz, :qux)
#   end
#
#   foo = Foo.new(bar: 123, baz: true)
#   foo.bar  # --> 123
#   foo.baz  # --> true
#   foo.qux  # --> nil
#   foo.fake # --> raises NoMethodError
module Percy
  class KeywordStruct < Struct
    def initialize(**kwargs)
      super(kwargs.keys)
      kwargs.each { |k, v| self[k] = v }
    end
  end
end
