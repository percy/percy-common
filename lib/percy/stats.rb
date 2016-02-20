require 'statsd'
require 'time'

module Percy
  class Stats < ::Statsd
    def initialize(*args)
      super
      self.tags = ["env:#{ENV['PERCY_ENV'] || 'development'}"]
    end

    # Equivalent to stats.time, but without wrapping in blocks and dealing with var scoping issues.
    #
    # @example Report the time taken to activate an account.
    #   stats.start_timing
    #   account.activate!
    #   stats.stop_timing('account.activate')
    def start_timing
      @_timing_start = Time.now
      true
    end

    def stop_timing(stat, options = {})
      raise 'no timing started' if !@_timing_start  # Programmer mistake, so raise an error.
      time_since(stat, @_timing_start, options)
      @_timing_start = nil
      true
    end
  end
end
