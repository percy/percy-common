require 'timeout'

module Percy
  class ProcessHelpers
    DEFAULT_TERM_GRACE_SECONDS = 10

    def self.gracefully_kill(pid, grace_period_seconds: DEFAULT_TERM_GRACE_SECONDS)
      begin
        Process.kill('TERM', pid)
        Timeout.timeout(grace_period_seconds) do
          Process.wait(pid)
        end
      rescue Errno::ESRCH
        # No such process.
        return false
      rescue Errno::ECHILD
        # Status has already been collected, perhaps by a Process.detach thread.
        return false
      rescue Timeout::Error
        begin
          Process.kill('KILL', pid)
        rescue Errno::ESRCH
          # If the process has already ended, suppress any additional errors
          return false
        end
        # Collect status so it doesn't stick around as zombie process.
        Process.wait(pid, Process::WNOHANG)
      end
      true
    end
  end
end
