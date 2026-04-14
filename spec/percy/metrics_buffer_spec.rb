require 'percy/metrics_buffer'

RSpec.describe Percy::MetricsBuffer do
  let(:buffer) { Percy::MetricsBuffer.new }

  describe '#gauge' do
    it 'stores the last value' do
      buffer.gauge('workers.idle', 8)
      data = buffer.flush!
      expect(data[:gauges]['workers.idle']).to eq(8)
    end

    it 'overwrites previous value' do
      buffer.gauge('workers.idle', 8)
      buffer.gauge('workers.idle', 12)
      data = buffer.flush!
      expect(data[:gauges]['workers.idle']).to eq(12)
    end

    it 'stores tagged gauges with composite key' do
      buffer.gauge('queue_size', 5, tags: ['sub:123'])
      data = buffer.flush!
      expect(data[:gauges]['queue_size[sub:123]']).to eq(5)
    end
  end

  describe '#increment' do
    it 'accumulates counts' do
      buffer.increment('heartbeat')
      buffer.increment('heartbeat')
      buffer.increment('heartbeat')
      data = buffer.flush!
      expect(data[:counters]['heartbeat']).to eq(3)
    end

    it 'increments by custom amount' do
      buffer.increment('jobs.moved', by: 5)
      buffer.increment('jobs.moved', by: 3)
      data = buffer.flush!
      expect(data[:counters]['jobs.moved']).to eq(8)
    end

    it 'stores tagged counters with composite key' do
      buffer.increment('skipped', tags: ['org:123'])
      buffer.increment('skipped', tags: ['org:456'])
      data = buffer.flush!
      expect(data[:counters]['skipped[org:123]']).to eq(1)
      expect(data[:counters]['skipped[org:456]']).to eq(1)
    end
  end

  describe '#count' do
    it 'adds value to counter' do
      buffer.count('locks.expired', 30)
      data = buffer.flush!
      expect(data[:counters]['locks.expired']).to eq(30)
    end

    it 'accumulates across multiple calls' do
      buffer.count('sleeptime', 2)
      buffer.count('sleeptime', 3)
      data = buffer.flush!
      expect(data[:counters]['sleeptime']).to eq(5)
    end
  end

  describe '#time' do
    it 'executes the block and returns its result' do
      result = buffer.time('insert_job') { 42 }
      expect(result).to eq(42)
    end

    it 'records duration in timers' do
      buffer.time('insert_job') { sleep(0.01) }
      data = buffer.flush!
      timer = data[:timers]['insert_job']
      expect(timer).not_to be_nil
      expect(timer[:count]).to eq(1)
      expect(timer[:min]).to be >= 10 # at least 10ms
      expect(timer[:max]).to be >= 10
      expect(timer[:sum]).to be >= 10
    end

    it 'tracks min/max/sum/count/values across multiple calls' do
      buffer.timing('method', 5)
      buffer.timing('method', 100)
      buffer.timing('method', 3)

      data = buffer.flush!
      timer = data[:timers]['method']
      expect(timer[:min]).to eq(3)
      expect(timer[:max]).to eq(100)
      expect(timer[:sum]).to eq(108)
      expect(timer[:count]).to eq(3)
      expect(timer[:values]).to eq([5, 100, 3])
    end
  end

  describe 'MAX_TIMING_VALUES cap' do
    it 'limits stored values to prevent unbounded memory growth' do
      (Percy::MetricsBuffer::MAX_TIMING_VALUES + 500).times do |i|
        buffer.timing('capped_metric', i)
      end

      data = buffer.flush!
      timer = data[:timers]['capped_metric']

      # min/max/sum/count are always accurate regardless of cap
      expect(timer[:count]).to eq(Percy::MetricsBuffer::MAX_TIMING_VALUES + 500)
      expect(timer[:min]).to eq(0)
      expect(timer[:max]).to eq(Percy::MetricsBuffer::MAX_TIMING_VALUES + 499)

      # values array is capped
      expect(timer[:values].length).to eq(Percy::MetricsBuffer::MAX_TIMING_VALUES)
    end
  end

  describe '#histogram' do
    it 'records value in timers hash' do
      buffer.histogram('startup_time', 30)
      data = buffer.flush!
      timer = data[:timers]['startup_time']
      expect(timer[:min]).to eq(30)
      expect(timer[:max]).to eq(30)
      expect(timer[:count]).to eq(1)
    end
  end

  describe '#timing' do
    it 'records a timing value directly' do
      buffer.timing('release_job', 42)
      data = buffer.flush!
      expect(data[:timers]['release_job'][:sum]).to eq(42)
    end
  end

  describe '#start_timing / #stop_timing' do
    it 'records duration between start and stop' do
      buffer.start_timing
      sleep(0.01)
      buffer.stop_timing('my_operation')
      data = buffer.flush!
      expect(data[:timers]['my_operation'][:count]).to eq(1)
      expect(data[:timers]['my_operation'][:min]).to be >= 10
    end

    it 'raises if no timing started' do
      expect { buffer.stop_timing('foo') }.to raise_error(RuntimeError, 'no timing started')
    end

    it 'clears timing after stop so it cannot be called again' do
      buffer.start_timing
      buffer.stop_timing('step1')
      expect { buffer.stop_timing('step2') }.to raise_error(RuntimeError)
    end
  end

  describe '#time_since_monotonic' do
    it 'records time since a monotonic clock start' do
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      sleep(0.01)
      buffer.time_since_monotonic('operation', start)
      data = buffer.flush!
      expect(data[:timers]['operation'][:min]).to be >= 10
    end

    it 'raises if start is not Float' do
      expect { buffer.time_since_monotonic('op', Time.now) }.to raise_error(ArgumentError)
    end
  end

  describe '#time_since' do
    it 'records time since a Time start' do
      start = Time.now
      sleep(0.01)
      buffer.time_since('operation', start)
      data = buffer.flush!
      expect(data[:timers]['operation'][:min]).to be >= 10
    end

    it 'raises if start is not Time' do
      expect { buffer.time_since('op', 123.0) }.to raise_error(ArgumentError)
    end
  end

  describe '#flush!' do
    it 'returns all data and resets counters/timers but persists gauges' do
      buffer.gauge('idle', 8)
      buffer.increment('heartbeat')
      buffer.timing('insert_job', 5)

      data = buffer.flush!
      expect(data[:gauges]).to eq({ 'idle' => 8 })
      expect(data[:counters]).to eq({ 'heartbeat' => 1 })
      expect(data[:timers]['insert_job'][:sum]).to eq(5)

      data2 = buffer.flush!
      expect(data2[:gauges]).to eq({ 'idle' => 8 })
      expect(data2[:counters]).to be_empty
      expect(data2[:timers]).to be_empty
    end

    it 'returns empty hashes when buffer is empty' do
      data = buffer.flush!
      expect(data[:gauges]).to be_empty
      expect(data[:counters]).to be_empty
      expect(data[:timers]).to be_empty
    end
  end

  describe 'thread safety' do
    it 'handles concurrent increments correctly' do
      threads = 10.times.map do
        Thread.new do
          1000.times { buffer.increment('counter') }
        end
      end
      threads.each(&:join)

      data = buffer.flush!
      expect(data[:counters]['counter']).to eq(10_000)
    end

    it 'handles concurrent mixed operations' do
      threads = []
      threads << Thread.new { 100.times { buffer.gauge('g', rand(100)) } }
      threads << Thread.new { 100.times { buffer.increment('c') } }
      threads << Thread.new { 100.times { buffer.timing('t', rand(100)) } }
      threads.each(&:join)

      data = buffer.flush!
      expect(data[:gauges]).to have_key('g')
      expect(data[:counters]['c']).to eq(100)
      expect(data[:timers]['t'][:count]).to eq(100)
    end
  end

  describe 'default_tags' do
    it 'has environment tag by default' do
      expect(buffer.default_tags).to include(match(/^env:/))
    end

    it 'accepts custom tags' do
      custom = Percy::MetricsBuffer.new(tags: ['env:production', 'service:hub'])
      expect(custom.default_tags).to eq(['env:production', 'service:hub'])
    end
  end
end
