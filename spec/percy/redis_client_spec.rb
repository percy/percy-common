# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/percy/redis_client.rb'

RSpec.describe Percy::RedisClient do
  attr_reader :port

  shared_examples 'redis client' do
    it 'returns a ::Redis instance' do
      instance = Percy::RedisClient.new(options)

      expect(instance.client).to be_a ::Redis
      expect(instance.client.ping).to eq 'PONG'
    end
  end

  context 'without SSL' do
    around(:each) do |ex|
      RedisMock.start(ping: proc { '+PONG' }) do |port|
        @port = port
        ex.run
        @port = nil
      end
    end

    context 'without a redis URL' do
      context 'without any options' do
        let(:options) { {} }

        it 'reverts to the default host and port' do
          instance = Percy::RedisClient.new(options)

          expect(instance.client).to be_a ::Redis
          expect(instance.client.connection.dig(:host)).to eq('127.0.0.1')
          expect(instance.client.connection.dig(:port)).to eq(6379)
        end
      end
    end

    context 'with a standard redis URL' do
      let(:redis_url) { "redis://127.0.0.1:#{port}" }

      context 'with just a URL' do
        let(:options) { {url: redis_url} }

        it_behaves_like 'redis client'
      end

      context 'with other options' do
        let(:options) { {url: redis_url, password: 1234, id: nil} }

        it_behaves_like 'redis client'
      end
    end
  end

  context 'with an SSL-enabled redis URL' do
    context 'with a mock redis server' do
      let(:redis_url) { "rediss://127.0.0.1:#{port}" }
      let(:options) { {url: redis_url} }

      around(:each) do |example|
        ENV['REDIS_SSL_CERTIFICATE_PATH'] = ssl_cert_path
        ENV['REDIS_SSL_PRIVATE_KEY_PATH'] = ssl_key_path
        ENV['REDIS_SSL_CERTIFICATE_AUTHORITY_PATH'] = ssl_ca_path
        ENV['REDIS_SSL_CLIENT_CERTIFICATE_PATH'] = ssl_cert_path
        RedisMock.start({ping: proc { '+PONG' }}, ssl_server_opts) do |port|
          @port = port
          example.run
          @port = nil
        end
        ENV['REDIS_SSL_CERTIFICATE_PATH'] = nil
        ENV['REDIS_SSL_PRIVATE_KEY_PATH'] = nil
        ENV['REDIS_SSL_CERTIFICATE_AUTHORITY_PATH'] = nil
        ENV['REDIS_SSL_CLIENT_CERTIFICATE_PATH'] = nil
      end

      it_behaves_like 'redis client'

      def ssl_server_opts
        {
          ssl: true,
          ssl_params: {
            ca_file: ssl_ca_path,
            cert: OpenSSL::X509::Certificate.new(File.read(ssl_cert_path)),
            key: OpenSSL::PKey::RSA.new(File.read(ssl_key_path)),
          },
        }
      end

      def ssl_cert_path
        File.join(cert_path, 'trusted-cert.crt')
      end

      def ssl_key_path
        File.join(cert_path, 'trusted-cert.key')
      end

      def ssl_ca_path
        File.join(cert_path, 'trusted-ca.crt')
      end

      def cert_path
        File.expand_path('../support/ssl', __dir__)
      end
    end
  end

  context 'with explicit SSL redis parameters' do
    context 'with a mock redis server' do
      let(:redis_url) { "rediss://127.0.0.1:#{port}" }
      let(:options) { ssl_server_opts.merge(url: redis_url) }
      let(:ssl_cert) { OpenSSL::X509::Certificate.new(File.read(ssl_cert_path)) }
      let(:ssl_key) { OpenSSL::PKey::RSA.new(File.read(ssl_key_path)) }

      around(:each) do |example|
        RedisMock.start({ping: proc { '+PONG' }}, ssl_server_opts) do |port|
          @port = port
          example.run
          @port = nil
        end
      end

      it_behaves_like 'redis client'

      it 'has the correct options' do
        expect(options[:url]).to eq(redis_url)
        expect(options[:ssl]).to eq(true)
        expect(options[:ssl_params][:ca_file]).to eq(ssl_ca_path)
        expect(options[:ssl_params][:cert]).to eq(ssl_cert)
        expect(options[:ssl_params][:key]).to eq(ssl_key)
      end

      def ssl_server_opts
        {
          ssl: true,
          ssl_params: {
            ca_file: ssl_ca_path,
            cert: ssl_cert,
            key: ssl_key,
          },
        }
      end

      def ssl_cert_path
        File.join(cert_path, 'trusted-cert.crt')
      end

      def ssl_key_path
        File.join(cert_path, 'trusted-cert.key')
      end

      def ssl_ca_path
        File.join(cert_path, 'trusted-ca.crt')
      end

      def cert_path
        File.expand_path('../support/ssl', __dir__)
      end
    end
  end
end
