require 'percy/metrics_flusher'

RSpec.describe Percy::MetricsFlusher do
  let(:buffer) { Percy::MetricsBuffer.new }
  let(:mock_client) { double('honeycomb_client') }
  let(:mock_event) { double('event', send: nil) }
  let(:flusher) do
    Percy::MetricsFlusher.new(
      buffer: buffer,
      honeycomb_client: mock_client,
      flush_interval: 0.1,
      service_name: 'percy-hub',
      event_name: 'hub_metrics_batch',
    )
  end

  before do
    allow(mock_client).to receive(:event).and_return(mock_event)
    allow(mock_event).to receive(:add_field)
  end

  describe '#start! and #stop!' do
    it 'starts and stops the flush thread' do
      flusher.start!
      expect(flusher.running?).to be true

      flusher.stop!
      expect(flusher.running?).to be false
    end
  end

  describe 'flushing gauge fields' do
    it 'sends gauge values as fields' do
      buffer.gauge('hub.workers.idle', 8)
      buffer.gauge('hub.workers.online', 2500)

      expect(mock_event).to receive(:add_field).with('hub.workers.idle', 8)
      expect(mock_event).to receive(:add_field).with('hub.workers.online', 2500)
      expect(mock_event).to receive(:add_field).with('name', 'hub_metrics_batch')
      expect(mock_event).to receive(:add_field).with('service_name', 'percy-hub')
      expect(mock_event).to receive(:add_field).with('env', anything)
      expect(mock_event).to receive(:send)

      flusher.send(:flush_once)
    end
  end

  describe 'flushing counter fields' do
    it 'sends counter values with _count suffix' do
      buffer.increment('hub.workers.heartbeat')
      buffer.increment('hub.workers.heartbeat')

      expect(mock_event).to receive(:add_field).with('hub.workers.heartbeat.count', 2)
      expect(mock_event).to receive(:add_field).with('name', 'hub_metrics_batch')
      expect(mock_event).to receive(:add_field).with('service_name', 'percy-hub')
      expect(mock_event).to receive(:add_field).with('env', anything)
      expect(mock_event).to receive(:send)

      flusher.send(:flush_once)
    end
  end

  describe 'flushing timer fields' do
    it 'sends timer values as avg/min/max/call_count fields' do
      buffer.timing('hub.methods.insert_job', 5)
      buffer.timing('hub.methods.insert_job', 100)
      buffer.timing('hub.methods.insert_job', 3)

      expect(mock_event).to receive(:add_field).with('hub.methods.insert_job.avg_ms', 36.0)
      expect(mock_event).to receive(:add_field).with('hub.methods.insert_job.min_ms', 3)
      expect(mock_event).to receive(:add_field).with('hub.methods.insert_job.max_ms', 100)
      expect(mock_event).to receive(:add_field).with('hub.methods.insert_job.call_count', 3)
      expect(mock_event).to receive(:add_field).with('hub.methods.insert_job.p50_ms', 5)
      expect(mock_event).to receive(:add_field).with('hub.methods.insert_job.p90_ms', 100)
      expect(mock_event).to receive(:add_field).with('hub.methods.insert_job.p99_ms', 100)
      expect(mock_event).to receive(:add_field).with('name', 'hub_metrics_batch')
      expect(mock_event).to receive(:add_field).with('service_name', 'percy-hub')
      expect(mock_event).to receive(:add_field).with('env', anything)
      expect(mock_event).to receive(:send)

      flusher.send(:flush_once)
    end
  end

  describe 'percentile calculation' do
    it 'computes correct percentiles with many values' do
      # 100 values: 1, 2, 3, ..., 100
      (1..100).each { |i| buffer.timing('hub.methods.test', i) }

      expect(mock_event).to receive(:add_field).with('hub.methods.test.p50_ms', 50)
      expect(mock_event).to receive(:add_field).with('hub.methods.test.p90_ms', 90)
      expect(mock_event).to receive(:add_field).with('hub.methods.test.p99_ms', 99)
      expect(mock_event).to receive(:add_field).with('hub.methods.test.avg_ms', 50.5)
      expect(mock_event).to receive(:add_field).with('hub.methods.test.min_ms', 1)
      expect(mock_event).to receive(:add_field).with('hub.methods.test.max_ms', 100)
      expect(mock_event).to receive(:add_field).with('hub.methods.test.call_count', 100)
      expect(mock_event).to receive(:add_field).with('name', 'hub_metrics_batch')
      expect(mock_event).to receive(:add_field).with('service_name', 'percy-hub')
      expect(mock_event).to receive(:add_field).with('env', anything)
      expect(mock_event).to receive(:send)

      flusher.send(:flush_once)
    end

    it 'handles single value' do
      buffer.timing('hub.methods.single', 42)

      expect(mock_event).to receive(:add_field).with('hub.methods.single.p50_ms', 42)
      expect(mock_event).to receive(:add_field).with('hub.methods.single.p90_ms', 42)
      expect(mock_event).to receive(:add_field).with('hub.methods.single.p99_ms', 42)
      expect(mock_event).to receive(:add_field).with('hub.methods.single.avg_ms', 42.0)
      expect(mock_event).to receive(:add_field).with('hub.methods.single.min_ms', 42)
      expect(mock_event).to receive(:add_field).with('hub.methods.single.max_ms', 42)
      expect(mock_event).to receive(:add_field).with('hub.methods.single.call_count', 1)
      expect(mock_event).to receive(:add_field).with('name', 'hub_metrics_batch')
      expect(mock_event).to receive(:add_field).with('service_name', 'percy-hub')
      expect(mock_event).to receive(:add_field).with('env', anything)
      expect(mock_event).to receive(:send)

      flusher.send(:flush_once)
    end
  end

  describe 'empty buffer' do
    it 'does not send an event when buffer is empty' do
      expect(mock_client).not_to receive(:event)
      flusher.send(:flush_once)
    end
  end

  describe 'error recovery' do
    it 'continues after HC send error' do
      buffer.gauge('test', 1)
      allow(mock_event).to receive(:send).and_raise(StandardError, 'network error')

      expect { flusher.send(:flush_once) }.not_to raise_error
    end

    it 'logs each failure below threshold' do
      allow(mock_event).to receive(:send).and_raise(StandardError, 'network error')

      expect($stderr).to receive(:puts).with(/MetricsFlusher flush error/).exactly(3).times

      3.times do
        buffer.gauge('test', 1)
        flusher.send(:flush_once)
      end
    end

    it 'logs threshold message at exactly N failures' do
      allow(mock_event).to receive(:send).and_raise(StandardError, 'network error')

      allow($stderr).to receive(:puts)
      expect($stderr).to receive(:puts).with(/has failed 10 consecutive flushes/).once

      10.times do
        buffer.gauge('test', 1)
        flusher.send(:flush_once)
      end
    end

    it 'stops logging individual errors after success resets count' do
      allow(mock_event).to receive(:send).and_raise(StandardError, 'network error')

      expect($stderr).to receive(:puts).with(/MetricsFlusher flush error/).once
      buffer.gauge('test', 1)
      flusher.send(:flush_once)

      allow(mock_event).to receive(:send) # success
      buffer.gauge('test', 1)
      flusher.send(:flush_once)

      # After reset, a new failure should log again (proves counter was reset)
      allow(mock_event).to receive(:send).and_raise(StandardError, 'network error')
      expect($stderr).to receive(:puts).with(/MetricsFlusher flush error/).once
      buffer.gauge('test', 1)
      flusher.send(:flush_once)
    end

    it 'continues flushing after background thread error' do
      call_count = 0
      allow(mock_event).to receive(:send) do
        call_count += 1
        raise StandardError, 'transient error' if call_count == 1
      end

      flusher.start!
      buffer.gauge('test', 1)
      sleep(0.25) # wait for at least 2 flush cycles

      buffer.gauge('test', 2)
      sleep(0.15)

      flusher.stop!
      expect(call_count).to be >= 2 # continued after error
    end
  end

  describe 'stop! does final flush' do
    it 'flushes remaining data on stop' do
      buffer.gauge('hub.workers.idle', 42)

      expect(mock_event).to receive(:add_field).with('hub.workers.idle', 42)
      expect(mock_event).to receive(:add_field).with('name', 'hub_metrics_batch')
      expect(mock_event).to receive(:add_field).with('service_name', 'percy-hub')
      expect(mock_event).to receive(:add_field).with('env', anything)
      expect(mock_event).to receive(:send)

      flusher.start!
      flusher.stop!
    end
  end

  describe 'tagged metrics aggregation' do
    it 'sums counters across tag combos' do
      buffer.increment('hub.skipped', tags: ['org:123'])
      buffer.increment('hub.skipped', tags: ['org:123'])
      buffer.increment('hub.skipped', tags: ['org:456'])

      expect(mock_event).to receive(:add_field).with('hub.skipped.count', 3) # total sum
      expect(mock_event).to receive(:add_field).with('hub.skipped.org.123.count', 2) # per-tag
      expect(mock_event).to receive(:add_field).with('hub.skipped.org.456.count', 1) # per-tag
      expect(mock_event).to receive(:add_field).with('name', 'hub_metrics_batch')
      expect(mock_event).to receive(:add_field).with('service_name', 'percy-hub')
      expect(mock_event).to receive(:add_field).with('env', anything)
      expect(mock_event).to receive(:send)

      flusher.send(:flush_once)
    end

    it 'preserves gauge values per tag' do
      buffer.gauge('hub.queue_size', 5, tags: ['sub:123'])
      buffer.gauge('hub.queue_size', 3, tags: ['sub:456'])

      expect(mock_event).to receive(:add_field).with('hub.queue_size', 3) # last value
      expect(mock_event).to receive(:add_field).with('hub.queue_size.sub.123', 5) # per-tag
      expect(mock_event).to receive(:add_field).with('hub.queue_size.sub.456', 3) # per-tag
      expect(mock_event).to receive(:add_field).with('name', 'hub_metrics_batch')
      expect(mock_event).to receive(:add_field).with('service_name', 'percy-hub')
      expect(mock_event).to receive(:add_field).with('env', anything)
      expect(mock_event).to receive(:send)

      flusher.send(:flush_once)
    end
  end

  describe 'configurable service_name and event_name' do
    it 'uses custom names' do
      custom_flusher = Percy::MetricsFlusher.new(
        buffer: buffer,
        honeycomb_client: mock_client,
        service_name: 'percy-api',
        event_name: 'api_metrics_batch',
      )

      buffer.gauge('test', 1)

      expect(mock_event).to receive(:add_field).with('name', 'api_metrics_batch')
      expect(mock_event).to receive(:add_field).with('service_name', 'percy-api')
      expect(mock_event).to receive(:add_field).with('test', 1)
      expect(mock_event).to receive(:add_field).with('env', anything)
      expect(mock_event).to receive(:send)

      custom_flusher.send(:flush_once)
    end
  end

  describe 'flush_interval' do
    it 'defaults to METRICS_FLUSH_INTERVAL_SECONDS env var or 3' do
      default_flusher = Percy::MetricsFlusher.new(
        buffer: buffer,
        honeycomb_client: mock_client,
      )
      expect(default_flusher.flush_interval).to eq(3)
    end

    it 'accepts custom interval' do
      expect(flusher.flush_interval).to eq(0.1)
    end
  end
end
