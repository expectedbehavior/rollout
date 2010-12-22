$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'rubygems'
require 'bundler/setup'
require 'rollout'
require 'spec'
require 'spec/autorun'
require 'bourne'
require 'redis'
require 'memcached'

$memcache_config = {
  :servers => ['localhost:11211']
}

Spec::Runner.configure do |config|
  config.mock_with :rspec
  config.before do
    Redis.new.flushdb 
    Memcached::Rails.new($memcache_config[:servers]).flush_all
  end
end
