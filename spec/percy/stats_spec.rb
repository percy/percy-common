require 'percy/stats'

RSpec.describe Percy::Stats do
  let(:stats) { Percy::Stats.new }

  context 'without env vars' do
    it 'sets host and port from defaults' do
      expect(stats.host).to eq('127.0.0.1')
      expect(stats.port).to eq(8125)
    end
  end

  context 'with env vars' do
    before(:each) do
      ENV['DATADOG_AGENT_HOST'] = 'localhost'
      ENV['DATADOG_AGENT_PORT'] = '1000'
    end
    after(:each) do
      ENV.delete('DATADOG_AGENT_HOST')
      ENV.delete('DATADOG_AGENT_PORT')
    end

    it 'sets host and port from env vars' do
      expect(stats.host).to eq('localhost')
      expect(stats.port).to eq(1000)
    end

    context 'with a network failure' do
      let(:retries_count) { 2 }
      let(:stats) { Percy::Stats.new('foo', 1000, retry_count: retries_count, retry_delay: 0) }

      it 'sets the host to localhost after retries are exceeded' do
        expect_any_instance_of(
          Datadog::Statsd,
        ).to receive(:connect_to_socket).at_least(retries_count).times.and_call_original

        expect(stats.host).to eq('localhost')
      end
    end
  end

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
