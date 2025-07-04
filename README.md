# percy-common

Server-side common library for Percy.

## Installation

Add this line to your application's Gemfile:

```
gem 'percy-common'
```

Or, for a Ruby library, add this to your gemspec:

```ruby
spec.add_development_dependency 'percy-common'
```

And then run

```bash
$ bundle install
```

### Setup in a Rails app

If including in a Rails app, add the following to your `application.rb`:

```ruby
require 'percy/common/engine'
```

This enables Rails to autoload the constants from this library without more `require` lines.

## Usage

### Percy::KeywordStruct

A simple struct that can be used when you need to return a simple value object.

```ruby
require 'percy/keyword_struct'

class Foo < Percy::KeywordStruct.new(:bar, :baz, :qux)
end

foo = Foo.new(bar: 123, baz: true)
foo.bar  # --> 123
foo.baz  # --> true
foo.qux  # --> nil
foo.fake # --> raises NoMethodError
```

### Percy.logger

```ruby
require 'percy/logger'

Percy.logger.debug { 'debug log' }
Percy.logger.info { 'info log' }
Percy.logger.warn { 'warning log' }
Percy.logger.error { 'error message' }
```

Prefer the block form usage `Percy.logger.debug { 'message' }` over `Percy.logger.debug('message')` because it is slightly more efficient when the log will be excluded by the current logging level. For example, if the log level is currently `info`, then a `debug` log in block form will never evaluate or allocate the message string itself.

### Percy::ProcessHelpers

#### `gracefully_kill(pid[, grace_period_seconds: 10])`

Returns `true` if the process was successfully killed, or `false` if the process did not exist or its exit status was already collected.

```ruby
require 'percy/process_helpers'

Percy::ProcessHelpers.gracefully_kill(pid)
```

This will send `SIGTERM` to the process, wait up to 10 seconds, then send `SIGKILL` if it has not already shut down.

### Percy::NetworkHelpers

#### `random_open_port`

Returns a random open port. This is guaranteed by the OS to be currently an unbound open port, but users must still handle race conditions where the port is bound by the time it is actually used.

```ruby
require 'percy/network_helpers'

Percy::NetworkHelpers.random_open_port
```

#### `verify_healthcheck(url:[, expected_body: 'ok', retry_wait_seconds: 0.5])`

Verify that a URL returns a specific body. Raises `Percy::NetworkHelpers::ServerDown` if the server is down or does not respond with the expected body.

```ruby
require 'percy/network_helpers'

Percy::NetworkHelpers.verify_healthcheck('http://localhost/healthz')
```

#### `verify_http_server_up(hostname[, port: nil, path: nil, retry_wait_seconds: 0.25])`

Verifies that a simple HTTP GET / request works against a hostname. Raises `Percy::NetworkHelpers::ServerDown` if the server is down or if the request times out.

```ruby
require 'percy/network_helpers'

Percy::NetworkHelpers.verify_http_server_up('example.com')
Percy::NetworkHelpers.verify_http_server_up('localhost', port: 8080)
```

#### `serve_static_directory(dir[, hostname: 'localhost', port: nil])`

Starts a simple local WEBrick server to serve a directory of static assets. This is a testing helper and should not be used in production.

```ruby
require 'percy/network_helpers'

Percy::NetworkHelpers.serve_static_directory(File.expand_path('../test_data/', __FILE__))
```

### Percy::Stats

Client for recording Datadog metrics and automatically setting up Percy-specific environment tags.

This class is a wrapper for [Datadog::Statsd](https://github.com/DataDog/dogstatsd-ruby), an extended client for DogStatsD, which extends the StatsD metric server for Datadog.

Basic usage includes:

```ruby
require 'percy/stats'

stats = Percy::Stats.new

# Increment a counter.
stats.increment('page.views')

# Record a gauge 50% of the time.
stats.gauge('users.online', 123, sample_rate: 0.5)

# Sample a histogram.
stats.histogram('file.upload.size', 1234)

# Time a block of code.
stats.time('page.render') do
  render_page('home.html')
end

# Send several metrics at the same time.
# All metrics will be buffered and sent in one packet when the block completes.
stats.batch do |s|
  s.increment('page.views')
  s.gauge('users.online', 123)
end

# Tag a metric.
stats.histogram('query.time', 10, tags: ['version:1'])
```

See the [Datadog::Statsd](https://github.com/DataDog/dogstatsd-ruby) docs for more usage.

Our wrapper adds support for a non-block based `start_timing` and `stop_timing` methods:

```ruby
require 'percy/stats'

stats = Percy::Stats.new

stats.start_timing
account.activate!
stats.stop_timing('account.activate')
```
