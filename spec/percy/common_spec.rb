require 'spec_helper'

RSpec.describe Percy::Common do
  it 'has a version number' do
    expect(Percy::Common::VERSION).to_not be_nil
  end
end
