require 'webrick'
require 'percy/process_helpers'
require 'percy/network_helpers'

RSpec.describe Percy::NetworkHelpers do
  let(:server_port) { Percy::NetworkHelpers.random_open_port }

  shared_context 'has a test HTTP server' do
    let(:server_url) { "http://localhost:#{server_port}" }
    let(:server) { WEBrick::HTTPServer.new(Port: server_port) }

    before(:each) do
      server.mount_proc('/') { |_request, response| response.body = 'hello world' }
      server.mount_proc('/healthz') { |_request, response| response.body = 'ok' }
      Thread.new { server.start }
      sleep 0.25 # Give the server time to boot.
    end
    after(:each) do
      server.shutdown
    end
  end

  describe '#random_open_port' do
    it 'returns a random open port in the desired range' do
      expect(Percy::NetworkHelpers.random_open_port).to be >= described_class::MIN_PORT
      expect(Percy::NetworkHelpers.random_open_port).to be <= described_class::MAX_PORT
    end
  end

  describe '#port_open?' do
    let(:port) { 7070 }

    it 'tells you if a port is open or not' do
      # Block the port and check it's not open
      server = TCPServer.open port
      expect(Percy::NetworkHelpers.port_open?(port)).to eq(false)

      # Unblock the port and check it's open now
      server.close
      expect(Percy::NetworkHelpers.port_open?(port)).to eq(true)
    end
  end

  describe '#verify_healthcheck' do
    include_context 'has a test HTTP server'

    it 'returns true if server is up and responds to healthcheck' do
      expect(Percy::NetworkHelpers.verify_healthcheck(url: server_url + '/healthz')).to eq(true)
    end
    it 'raises error if server fails healthcheck' do
      expect do
        Percy::NetworkHelpers.verify_healthcheck(url: server_url + '/', retry_wait_seconds: 0)
      end.to raise_error(Percy::NetworkHelpers::ServerDown)
    end
  end
  describe '#verify_http_server_up' do
    context 'when server is up' do
      include_context 'has a test HTTP server'

      it 'returns true if server is up and responds to healthcheck' do
        result = Percy::NetworkHelpers.verify_http_server_up('localhost', port: server_port)
        expect(result).to eq(true)
      end
    end
    it 'raises error if server is not up' do
      expect do
        Percy::NetworkHelpers.verify_http_server_up(
          'localhost',
          port: server_port,
          retry_wait_seconds: 0,
        )
      end.to raise_error(Percy::NetworkHelpers::ServerDown)
    end
  end
  describe '#serve_static_directory' do
    let(:test_data_dir) { File.expand_path('../test_data/', __FILE__) }

    it 'serves a static directory' do
      pid = Percy::NetworkHelpers.serve_static_directory(test_data_dir)
      Percy::ProcessHelpers.gracefully_kill(pid)
    end
  end
end
