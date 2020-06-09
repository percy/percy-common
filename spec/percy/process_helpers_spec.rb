require 'percy/process_helpers'

RSpec.describe Percy::ProcessHelpers do
  let(:non_existent_pid) { 11111111 }

  describe '#gracefully_kill' do
    it 'returns true if the subprocess is successfully killed' do
      pid = fork { sleep 2 }
      expect(Percy::ProcessHelpers.gracefully_kill(pid)).to eq(true)
    end

    it 'returns true if the subprocess is successfully killed after timeout' do
      pid = fork { Signal.trap(:TERM) { sleep 20 } }
      start = Time.now
      expect(Percy::ProcessHelpers.gracefully_kill(pid, grace_period_seconds: 0.5)).to eq(true)
      expect(Time.now - start).to be > 0.5
    end

    it 'returns false if process does not exist' do
      expect(Percy::ProcessHelpers.gracefully_kill(non_existent_pid)).to eq(false)
    end

    it 'returns false if exit code has already been collected' do
      pid = fork {}
      Process.wait(pid)
      expect(Percy::ProcessHelpers.gracefully_kill(pid)).to eq(false)
    end
  end
end
