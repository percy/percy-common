require 'time'

module Percy
  class MetricsBuffer
    DEFAULT_TAGS = %W[
      env:#{ENV.fetch('PERCY_ENV', 'development')}
    ].freeze

    # Max timing values stored per metric per flush window.
    # Prevents unbounded memory growth if flush thread dies or a code bug
    # creates a tight loop. 1000 values = ~8KB per metric, enough for
    # accurate p99 with 3-sec flush (~150 calls/sec typical max).
    MAX_TIMING_VALUES = 1000

    attr_reader :default_tags

    def initialize(tags: DEFAULT_TAGS)
      @default_tags = tags
      @gauges = {}
      @counters = {}
      @timers = {}
      @mutex = Mutex.new
    end

    # Store the last value for a gauge metric.
    # Same signature as Datadog::Statsd#gauge
    def gauge(stat, value, opts = {})
      key = build_key(stat, opts)
      @mutex.synchronize { @gauges[key] = value }
    end

    # Increment a counter metric.
    # Same signature as Datadog::Statsd#increment
    def increment(stat, opts = {})
      by = opts[:by] || 1
      key = build_key(stat, opts)
      @mutex.synchronize { @counters[key] = (@counters[key] || 0) + by }
    end

    # Set a counter to a specific value.
    # Same signature as Datadog::Statsd#count
    def count(stat, value, opts = {})
      key = build_key(stat, opts)
      @mutex.synchronize { @counters[key] = (@counters[key] || 0) + value }
    end

    # Time a block and record the duration.
    # Same signature as Datadog::Statsd#time — returns the block's return value.
    # Uses ensure so timing is recorded even when the block uses `return`
    # (which exits the enclosing method, skipping code after yield).
    def time(stat, opts = {})
      start = now
      yield
    ensure
      duration_ms = ((now - start) * 1000).round

      key = build_key(stat, opts)
      @mutex.synchronize do
        record_timing(key, duration_ms)
      end
    end

    # Record a histogram value.
    # Same signature as Datadog::Statsd#histogram
    def histogram(stat, value, opts = {})
      key = build_key(stat, opts)
      @mutex.synchronize do
        record_timing(key, value)
      end
    end

    # Record a timing value directly (used by time_since_monotonic, time_since).
    # Same signature as Datadog::Statsd#timing
    def timing(stat, value, opts = {})
      key = build_key(stat, opts)
      @mutex.synchronize do
        record_timing(key, value)
      end
    end

    # Start a manual timing session.
    # Thread-local to avoid cross-thread interference.
    # Same as Percy::Stats#start_timing
    def start_timing
      Thread.current[:_metrics_buffer_timing_start] = now
      true
    end

    # Stop timing and record the duration.
    # Same as Percy::Stats#stop_timing
    def stop_timing(stat, options = {})
      start = Thread.current[:_metrics_buffer_timing_start]
      raise 'no timing started' unless start

      time_since_monotonic(stat, start, options)
      Thread.current[:_metrics_buffer_timing_start] = nil
      true
    end

    # Record time elapsed since a monotonic clock start.
    # Same as Percy::Stats#time_since_monotonic
    def time_since_monotonic(stat, start, opts = {})
      unless start.instance_of? Float
        raise ArgumentError, 'start value must be Float'
      end

      timing(stat, ((now.to_f - start.to_f) * 1000).round, opts)
    end

    # Record time elapsed since a Time start.
    # Same as Percy::Stats#time_since
    def time_since(stat, start, opts = {})
      unless start.instance_of? Time
        raise ArgumentError, 'start value must be Time'
      end

      timing(stat, ((Time.now.to_f - start.to_f) * 1000).round, opts)
    end

    # Atomically flush all buffered data and reset.
    # Returns { gauges: {}, counters: {}, timers: {} }
    def flush!
      @mutex.synchronize do
        snapshot = {
          gauges: @gauges.dup,
          counters: @counters.dup,
          timers: @timers.dup,
        }
        @gauges.clear
        @counters.clear
        @timers.clear
        snapshot
      end
    end

    private

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def build_key(stat, opts = {})
      tags = opts[:tags]
      if tags && !tags.empty?
        # Normalize Hash tags to key:value strings
        normalized = if tags.is_a?(Hash)
          tags.map { |k, v| "#{k}:#{v}" }
        else
          Array(tags)
        end
        tag_str = normalized.sort.join(',')
        "#{stat}[#{tag_str}]"
      else
        stat.to_s
      end
    end

    def record_timing(key, value)
      if @timers[key]
        t = @timers[key]
        t[:min] = value if value < t[:min]
        t[:max] = value if value > t[:max]
        t[:sum] += value
        t[:count] += 1
        # Cap values array to prevent unbounded memory growth.
        # min/max/sum/count are always accurate; percentiles use
        # a reservoir sample when capped.
        t[:values] << value if t[:values].length < MAX_TIMING_VALUES
      else
        @timers[key] = { min: value, max: value, sum: value, count: 1, values: [value] }
      end
    end
  end
end
