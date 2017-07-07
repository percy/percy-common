require 'percy/logger'

RSpec.describe 'Percy.logger' do
  it 'works' do
    Percy.logger.warn('test warning log')
  end
end
