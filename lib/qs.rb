require 'ns-options'
require 'qs/version'
require 'qs/client'
require 'qs/daemon'
require 'qs/dispatcher_queue'
require 'qs/job_handler'
require 'qs/queue'

module Qs

  def self.config; @config ||= Config.new; end
  def self.configure(&block)
    block.call(self.config)
  end

  def self.init
    self.config.redis.url ||= RedisUrl.new(
      self.config.redis.ip,
      self.config.redis.port,
      self.config.redis.db
    )

    @dispatcher_queue ||= DispatcherQueue.new({
      :queue_class            => self.config.dispatcher_queue_class,
      :queue_name             => self.config.dispatcher.queue_name,
      :job_name               => self.config.dispatcher.job_name,
      :job_handler_class_name => self.config.dispatcher.job_handler_class_name
    })

    @encoder ||= self.config.encoder
    @decoder ||= self.config.decoder
    @client  ||= Client.new(self.redis_config)
    @redis   ||= @client.redis
    true
  end

  def self.reset!
    self.config.reset
    @dispatcher_queue = nil
    @encoder          = nil
    @decoder          = nil
    @client           = nil
    @redis            = nil
    true
  end

  def self.enqueue(queue, job_name, params = nil)
    @client.enqueue(queue, job_name, params)
  end

  def self.publish(channel, name, params = nil)
    @client.publish(channel, name, params)
  end

  def self.publish_as(publisher, channel, name, params = nil)
    @client.publish_as(publisher, channel, name, params)
  end

  def self.push(queue_name, payload)
    @client.push(queue_name, payload)
  end

  def self.encode(payload)
    @encoder.call(payload)
  end

  def self.decode(encoded_payload)
    @decoder.call(encoded_payload)
  end

  def self.sync_subscriptions(queue)
    self.client.sync_subscriptions(queue)
  end

  def self.clear_subscriptions(queue)
    self.client.clear_subscriptions(queue)
  end

  def self.event_subscribers(event)
    self.client.event_subscribers(event)
  end

  def self.client
    @client
  end

  def self.redis
    @redis
  end

  def self.redis_config
    self.config.redis.to_hash
  end

  def self.dispatcher_queue
    @dispatcher_queue
  end

  def self.dispatcher_job_name
    self.config.dispatcher.job_name
  end

  def self.event_publisher
    self.config.event_publisher
  end

  def self.published_events
    self.dispatcher_queue.published_events
  end

  class Config
    include NsOptions::Proxy

    option :encoder, Proc, :default => proc{ |p| ::JSON.dump(p) }
    option :decoder, Proc, :default => proc{ |p| ::JSON.load(p) }

    option :timeout, Float

    option :event_publisher, String

    namespace :dispatcher do
      option :queue_name,             String, :default => 'dispatcher'
      option :job_name,               String, :default => 'run_dispatch_job'
      option :job_handler_class_name, String, :default => DispatcherQueue::RunDispatchJob.to_s
    end

    namespace :redis do
      option :ip,   :default => 'localhost'
      option :port, :default => 6379
      option :db,   :default => 0

      option :url

      option :redis_ns, String,  :default => 'qs'
      option :driver,   String,  :default => 'ruby'
      option :timeout,  Integer, :default => 1
      option :size,     Integer, :default => 4
    end

    attr_accessor :dispatcher_queue_class

    def initialize
      self.dispatcher_queue_class = Queue
    end
  end

  module RedisUrl
    def self.new(ip, port, db)
      return if ip.to_s.empty? || port.to_s.empty? || db.to_s.empty?
      "redis://#{ip}:#{port}/#{db}"
    end
  end

end
