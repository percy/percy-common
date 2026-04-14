require 'percy/metrics_buffer'

module Percy
  class MetricsFlusher
    DEFAULT_FLUSH_INTERVAL = Integer(
      ENV.fetch('METRICS_FLUSH_INTERVAL_SECONDS', 3),
    )

    attr_reader :flush_interval

    FAILURE_LOG_THRESHOLD = 10

    def initialize(
      buffer:,
      honeycomb_client:,
      flush_interval: DEFAULT_FLUSH_INTERVAL,
      service_name: 'percy-hub',
      event_name: 'metrics_batch',
      logger: nil
    )
      @buffer = buffer
      @honeycomb_client = honeycomb_client
      @flush_interval = flush_interval
      @service_name = service_name
      @event_name = event_name
      @logger = logger
      @running = false
      @thread = nil
      @mutex = Mutex.new
      @flush_mutex = Mutex.new
      @consecutive_failures = 0
    end

    def start!
      @mutex.synchronize do
        return if @running

        @running = true
        @thread = Thread.new { flush_loop }
        @thread.abort_on_exception = false
      end
      self
    end

    def stop!
      @mutex.synchronize { @running = false }
      thread_exited = @thread&.join(@flush_interval + 2)
      # Only do a final flush if the thread actually exited (join didn't timeout),
      # otherwise the thread may still be mid-flush.
      flush_once if thread_exited || @thread.nil?
      self
    end

    def running?
      @mutex.synchronize { @running }
    end

    def consecutive_failures
      @consecutive_failures
    end

    private

    def flush_loop
      while @mutex.synchronize { @running }
        sleep(@flush_interval)
        flush_once
      end
    rescue StandardError => e
      log_error("MetricsFlusher thread died unexpectedly: #{e.class}: #{e.message}")
    ensure
      @mutex.synchronize { @running = false }
    end

    def flush_once
      @flush_mutex.synchronize do
        data = @buffer.flush!

        # Skip if nothing to send
        return if data[:gauges].empty? && data[:counters].empty? && data[:timers].empty?

        event = @honeycomb_client.event
        event.add_field('name', @event_name)
        event.add_field('service_name', @service_name)

        # Add default tags as fields
        @buffer.default_tags.each do |tag|
          key, value = tag.split(':', 2)
          event.add_field(key, value)
        end

        # Gauges: for tagged metrics, aggregate by base name (last value wins per base)
        # and preserve unique tag combos as separate fields
        aggregate_and_add_fields(event, data[:gauges], :gauge)

        # Counters: for tagged metrics, SUM across all tag combos per base name
        aggregate_and_add_fields(event, data[:counters], :counter)

        # Timers: expand to avg/min/max/p50/p90/p99/call_count
        data[:timers].each do |key, timer|
          base = key_to_field_name(key)
          avg = timer[:count] > 0 ? (timer[:sum].to_f / timer[:count]).round(2) : 0
          event.add_field("#{base}_avg_ms", avg)
          event.add_field("#{base}_min_ms", timer[:min])
          event.add_field("#{base}_max_ms", timer[:max])
          event.add_field("#{base}_call_count", timer[:count])

          # Percentiles from stored values
          if timer[:values] && timer[:values].length > 0
            sorted = timer[:values].sort
            event.add_field("#{base}_p50_ms", percentile(sorted, 50))
            event.add_field("#{base}_p90_ms", percentile(sorted, 90))
            event.add_field("#{base}_p99_ms", percentile(sorted, 99))
          end
        end

        event.send
        @consecutive_failures = 0
      end
    rescue StandardError => e
      @consecutive_failures += 1
      if @consecutive_failures == FAILURE_LOG_THRESHOLD
        log_error("MetricsFlusher has failed #{FAILURE_LOG_THRESHOLD} consecutive flushes: #{e.message}")
      elsif @consecutive_failures < FAILURE_LOG_THRESHOLD
        log_error("MetricsFlusher flush error: #{e.message}")
      end
      # Above threshold: log only every 100 failures to avoid log spam
      if @consecutive_failures > FAILURE_LOG_THRESHOLD && (@consecutive_failures % 100).zero?
        log_error("MetricsFlusher still failing (#{@consecutive_failures} consecutive): #{e.message}")
      end
    end

    # Aggregate tagged metrics by base name.
    # For counters: sum all tag combos into one total.
    # For gauges: use last value (hash iteration order).
    # Also emit per-tag fields when tags exist.
    def aggregate_and_add_fields(event, hash, type)
      # Group by base metric name (without tags)
      grouped = {}
      hash.each do |key, value|
        base = extract_base_name(key)
        tag = extract_tag(key)

        grouped[base] ||= { total: 0, tagged: {} }

        if type == :counter
          grouped[base][:total] += value
        else
          grouped[base][:total] = value
        end

        if tag
          grouped[base][:tagged][tag] = value
        end
      end

      grouped.each do |base, data|
        field_base = base.tr('.', '_')
        suffix = type == :counter ? '_count' : ''

        # Always emit the aggregated total
        event.add_field("#{field_base}#{suffix}", data[:total])

        # Also emit per-tag breakdown if there are tagged values
        data[:tagged].each do |tag, value|
          safe_tag = tag.tr(':', '_').tr(',', '_').tr('.', '_')
          event.add_field("#{field_base}_#{safe_tag}#{suffix}", value)
        end
      end
    end

    def extract_base_name(key)
      key.to_s.sub(/\[.*\]/, '')
    end

    def extract_tag(key)
      match = key.to_s.match(/\[(.+)\]/)
      match ? match[1] : nil
    end

    def key_to_field_name(key)
      extract_base_name(key).tr('.', '_')
    end

    # Calculate percentile from a sorted array.
    # Uses nearest-rank method: p-th percentile = value at ceil(p/100 * n) - 1
    def percentile(sorted_values, p)
      return sorted_values[0] if sorted_values.length == 1

      rank = (p / 100.0 * sorted_values.length).ceil - 1
      rank = [rank, 0].max
      sorted_values[rank]
    end

    def log_error(message)
      if @logger
        @logger.error(message)
      else
        $stderr.puts(message)
      end
    end
  end
end
