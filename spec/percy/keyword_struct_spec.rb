require 'percy/keyword_struct'

RSpec.describe Percy::KeywordStruct do
  it 'works' do
    class Foo < Percy::KeywordStruct.new(:bar, :baz, :qux)
    end

    foo = Foo.new(bar: 1, baz: 2)
    expect(foo.bar).to eq(1)
    expect(foo.baz).to eq(2)
    expect(foo.qux).to eq(nil)
    expect { foo.does_not_exist }.to raise_error(NoMethodError)
    expect { Foo.new(does_not_exist: 1) }.to raise_error(NameError)
  end
end
