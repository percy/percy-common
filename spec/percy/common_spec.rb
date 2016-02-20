require 'spec_helper'

RSpec.describe Percy::Common do
  it 'has a version number' do
    expect(Percy::Common::VERSION).not_to be nil
  end
end
