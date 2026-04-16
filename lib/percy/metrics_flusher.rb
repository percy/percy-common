require 'percy/metrics_buffer'

module Percy
  class MetricsFlusher
    DEFAULT_FLUSH_INTERVAL = Integer(
      ENV.fetch('METRICS_FLUSH_INTERVAL_SECONDS', 3),
    )

    attr_reader :flush_interval

    FAILURE_LOG_THRESHOLD = 10
    MAX_TAG_FIELDS = 100

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

    private def flush_loop
      while @mutex.synchronize { @running }
        sleep(@flush_interval)
        flush_once
      end
    rescue StandardError => e
      log_error("MetricsFlusher thread died: #{e.class}: #{e.message}, " \
                "restarting in #{@flush_interval}s")
      sleep(@flush_interval)
      retry if @mutex.synchronize { @running }
    ensure
      @mutex.synchronize { @running = false }
    end

    private def flush_once
      event = nil
      @flush_mutex.synchronize do
        data = @buffer.flush!

        return if data[:gauges].empty? && data[:counters].empty? && data[:timers].empty?

        event = build_event(data)
      end

      return unless event

      event.send
      @consecutive_failures = 0
    rescue StandardError => e
      @consecutive_failures += 1
      if @consecutive_failures == FAILURE_LOG_THRESHOLD
        log_error("MetricsFlusher has failed #{FAILURE_LOG_THRESHOLD} " \
                  "consecutive flushes: #{e.message}")
      elsif @consecutive_failures < FAILURE_LOG_THRESHOLD
        log_error("MetricsFlusher flush error: #{e.message}")
      end
      if @consecutive_failures > FAILURE_LOG_THRESHOLD && (@consecutive_failures % 100) == 0
        log_error('MetricsFlusher still failing ' \
                  "(#{@consecutive_failures} consecutive): #{e.message}")
      end
    end

    private def build_event(data)
      event = @honeycomb_client.event
      event.add_field('name', @event_name)
      event.add_field('service_name', @service_name)

      @buffer.default_tags.each do |tag|
        key, value = tag.split(':', 2)
        event.add_field(key, value)
      end

      aggregate_and_add_fields(event, data[:gauges], :gauge)
      aggregate_and_add_fields(event, data[:counters], :counter)

      data[:timers].each do |key, timer|
        base = key_to_field_name(key)
        avg = timer[:count] > 0 ? (timer[:sum].to_f / timer[:count]).round(2) : 0
        event.add_field("#{base}.avg_ms", avg)
        event.add_field("#{base}.min_ms", timer[:min])
        event.add_field("#{base}.max_ms", timer[:max])
        event.add_field("#{base}.call_count", timer[:count])

        next unless timer[:values] && !timer[:values].empty?

        sorted = timer[:values].sort
        event.add_field("#{base}.p50_ms", percentile(sorted, 50))
        event.add_field("#{base}.p90_ms", percentile(sorted, 90))
        event.add_field("#{base}.p99_ms", percentile(sorted, 99))
      end

      event
    end

    # Aggregate tagged metrics by base name.
    # For counters: sum all tag combos into one total.
    # For gauges: use last value (hash iteration order).
    # Also emit per-tag fields when tags exist.
    private def aggregate_and_add_fields(event, hash, type)
      grouped = {}
      hash.each do |key, value|
        key_str = key.to_s
        if key_str.include?('[')
          base = extract_base_name(key_str)
          tag = extract_tag(key_str)
        else
          base = key_str
          tag = nil
        end

        grouped[base] ||= {total: 0, tagged: {}}

        if type == :counter
          grouped[base][:total] += value
        else
          grouped[base][:total] = value
        end

        grouped[base][:tagged][tag] = value if tag
      end

      grouped.each do |base, data|
        suffix = type == :counter ? '.count' : ''

        event.add_field("#{base}#{suffix}", data[:total])

        if data[:tagged].size <= MAX_TAG_FIELDS
          data[:tagged].each do |tag, value|
            safe_tag = tag.tr(':', '.').tr(',', '.')
            event.add_field("#{base}.#{safe_tag}#{suffix}", value)
          end
        else
          log_error("Skipping per-tag breakdown for #{base}: " \
                    "#{data[:tagged].size} unique tags exceeds cap")
        end
      end
    end

    private def extract_base_name(key)
      key.to_s.sub(/\[.*\]/, '')
    end

    private def extract_tag(key)
      match = key.to_s.match(/\[(.+)\]/)
      match ? match[1] : nil
    end

    private def key_to_field_name(key)
      extract_base_name(key)
    end

    # Calculate percentile from a sorted array.
    # Uses nearest-rank method: p-th percentile = value at ceil(p/100 * n) - 1
    private def percentile(sorted_values, p)
      return sorted_values[0] if sorted_values.length == 1

      rank = (p / 100.0 * sorted_values.length).ceil - 1
      rank = [rank, 0].max
      sorted_values[rank]
    end

    private def log_error(message)
      if @logger
        @logger.error(message)
      else
        warn(message)
      end
    end
  end
end
