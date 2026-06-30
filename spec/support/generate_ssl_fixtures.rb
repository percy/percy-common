# frozen_string_literal: true

require 'fileutils'
require 'openssl'

# Generates the test-only TLS material under spec/support/ssl/ at suite time.
# Replaces the previously committed RSA private keys, which were flagged by
# PER-8502: keeping them out of git removes the supply-chain risk of an
# attacker cloning the repo and recovering a key trusted by any operator who
# accidentally imported trusted-ca.crt into a real trust store.
module SslFixtures
  SSL_DIR = File.expand_path('ssl', __dir__).freeze
  CA_CERT = File.join(SSL_DIR, 'trusted-ca.crt').freeze
  CA_KEY = File.join(SSL_DIR, 'trusted-ca.key').freeze
  SERVER_CERT = File.join(SSL_DIR, 'trusted-cert.crt').freeze
  SERVER_KEY = File.join(SSL_DIR, 'trusted-cert.key').freeze

  def self.ensure_generated!
    return if File.exist?(SERVER_KEY) && File.exist?(SERVER_CERT) &&
      File.exist?(CA_KEY) && File.exist?(CA_CERT)

    FileUtils.mkdir_p(SSL_DIR)

    ca_key = OpenSSL::PKey::RSA.new(2048)
    ca_cert = build_certificate(
      subject: '/CN=percy-common-test-ca',
      key: ca_key,
      issuer_cert: nil,
      issuer_key: ca_key,
      ca: true,
    )

    server_key = OpenSSL::PKey::RSA.new(2048)
    server_cert = build_certificate(
      subject: '/CN=127.0.0.1',
      key: server_key,
      issuer_cert: ca_cert,
      issuer_key: ca_key,
      ca: false,
    )

    write_pem(CA_CERT, ca_cert.to_pem)
    write_pem(CA_KEY, ca_key.to_pem)
    write_pem(SERVER_CERT, server_cert.to_pem)
    write_pem(SERVER_KEY, server_key.to_pem)
  end

  def self.build_certificate(subject:, key:, issuer_cert:, issuer_key:, ca:)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = OpenSSL::BN.rand(160)
    cert.subject = OpenSSL::X509::Name.parse(subject)
    cert.issuer = (issuer_cert || cert).subject
    cert.public_key = key.public_key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + (365 * 24 * 60 * 60)

    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = issuer_cert || cert

    if ca
      cert.add_extension(ef.create_extension('basicConstraints', 'CA:TRUE', true))
      cert.add_extension(ef.create_extension('keyUsage', 'keyCertSign, cRLSign', true))
    else
      cert.add_extension(ef.create_extension('basicConstraints', 'CA:FALSE', true))
      cert.add_extension(ef.create_extension('subjectAltName', 'IP:127.0.0.1', false))
    end

    cert.sign(issuer_key, OpenSSL::Digest.new('SHA256'))
    cert
  end

  def self.write_pem(path, pem)
    File.open(path, 'w', 0o600) { |f| f.write(pem) }
  end
end

SslFixtures.ensure_generated!
