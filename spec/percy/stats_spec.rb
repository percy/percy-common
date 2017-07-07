require 'percy/stats'

RSpec.describe Percy::Stats do
  let(:stats) { Percy::Stats.new }

  it 'sets environment tag' do
    expect(stats.tags).to eq(['env:test'])
  end
  describe 'start_timing' do
    it 'returns the current step index for the given stat' do
      expect(stats.start_timing).to eq(true)
    end
  end
  describe 'stop_timing' do
    it 'stops timing and records the time difference' do
      expect(stats).to receive(:time_since)
        .with('foo.bar.step1', instance_of(Time), priority: :low).and_call_original
      expect(stats).to receive(:time_since)
        .with('foo.bar.step2', instance_of(Time), priority: :low).and_call_original

      stats.start_timing
      stats.stop_timing('foo.bar.step1', priority: :low)
      stats.start_timing
      stats.stop_timing('foo.bar.step2', priority: :low)
    end
    it 'fails if no timing step is in progress' do
      expect { stats.stop_timing('foo.bar') }.to raise_error(RuntimeError)

      # Clears the current timing so it can't be called again:
      stats.start_timing
      stats.stop_timing('foo.bar.step1')
      expect { stats.stop_timing('foo.bar.step2') }.to raise_error(RuntimeError)
    end
  end
end
