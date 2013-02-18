require 'set'
require 'logger'
require 'stringio'
require 'ns-options'
require 'qs/version'
require 'qs/redis_connection'
require 'qs/queue'

module Qs

  def self.config; Config; end
  def self.configure(&block); Config.define(&block); end

  def self.init
    self.after_fork
  end

  def self.after_fork
    @redis = Qs::RedisConnection.new(Qs.config.redis)
  end

  # queues needs to be available lazyily -- queues may try to register
  # themselves with Qs before it has run its `init`

  def self.queues; @queues ||= QueueSet.new; end
  def self.register(queue); self.queues.add(queue); end

  def self.redis(&block)
    raise ArgumentError, "requires a block" if !block
    raise RuntimeError,  "no redis connection - call `Qs.init`" if @redis.nil?
    @redis.with(&block)
  end

  class Config
    include NsOptions::Proxy

    option :queue_key_prefix, String, :default => 'qs'
    option :platform,         String, :default => 'ruby'
    option :version,          String, :default => Qs::VERSION

    namespace :redis do
      option :url,      String, :default => 'redis://localhost:6379/0'
      option :redis_ns, String, :default => 'qs'
      option :size,     Fixnum, :default => 5
      option :timeout,  Fixnum, :default => 1
      option :driver,   String, :default => 'ruby'
    end

    option :timeout, Fixnum, :default => proc { Qs::Config.default_timeout }
    option :logger,          :default => proc { Qs::Config.null_logger }

    def self.default_timeout
      300 # seconds (5 mins)
    end

    def self.null_logger
      @null_logger ||= Logger.new(StringIO.new)
    end

  end

  class QueueSet < ::Set

    # manage subscriptions across all queues

    def list_subscriptions(out)
      self.each do |queue|
        log_subscriptions(out, queue)
      end
    end

    def sync_subscriptions(out)
      log out, "Syncing subscriptions for all queues..."

      self.each do |queue|
        queue.sync_subscriptions
        log_subscriptions(out, queue)
      end
    end

    def destroy_subscriptions(out)
      log out, "Removing subscriptions for all queues..."

      self.each do |queue|
        queue.destroy_subscriptions
        log_subscriptions(out, queue)
      end
    end

    private

    def log_subscriptions(out, queue)
      log out, "#{queue} (#{queue.redis_key}) subscriptions:"

      if (subs = queue.get_subscriptions).empty?
        log out, "\tno subscriptions"; return
      end

      event_ljust = subs.map{|event_key, handler_class| event_key.size}.max
      subs.each do |event_key, handler_class|
        log out, "\t#{event_key.ljust(event_ljust)} => #{handler_class}"
      end
    end

    def log(out, msg); out.puts(msg); end

  end

end
