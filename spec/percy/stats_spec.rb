require 'percy/stats'

RSpec.describe Percy::Stats do
  let(:stats) { Percy::Stats.new }

  context 'without env vars' do
    it 'sets host and port from defaults' do
      expect(stats.connection.host).to eq '127.0.0.1'
      expect(stats.connection.port).to eq 8125
    end
  end

  context 'with env vars' do
    before(:each) do
      stub_const 'Percy::Stats::DEFAULT_HOST', 'my.datadog.host'
      stub_const 'Percy::Stats::DEFAULT_PORT', 1000
    end

    it 'sets default host and port' do
      expect(stats.connection.host).to eq 'my.datadog.host'
      expect(stats.connection.port).to eq 1000
    end
  end

  it 'sets environment tag' do
    expect(stats.tags).to eq(['env:test'])
  end

  describe 'stop_timing' do
    it 'stops timing and records the time difference' do
      expect(stats).to receive(:time_since_monotonic)
        .with('foo.bar.step1', instance_of(Float), priority: :low).and_call_original
      expect(stats).to receive(:time_since_monotonic)
        .with('foo.bar.step2', instance_of(Float), priority: :low).and_call_original

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

  describe 'time_since' do
    let(:start) { Time.now }

    it 'returns an interval' do
      expect(stats.time_since('foo.bar', start)).to be_instance_of Integer
    end

    context 'with a float value' do
      let(:start) { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

      it 'raises ArgumentError' do
        expect { stats.time_since('foo.bar', start) }.to \
          raise_error(ArgumentError)
      end
    end
  end
end
