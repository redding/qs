require 'ns-options'
require 'qs/version'
require 'qs/client'
require 'qs/daemon'
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

    @dispatcher_queue ||= begin
      dispatcher_name = self.config.dispatcher_name
      Queue.new{ name(dispatcher_name) }
    end

    @serializer   ||= self.config.serializer
    @deserializer ||= self.config.deserializer
    @client       ||= Client.new(self.redis_config)
    @redis        ||= @client.redis
    true
  end

  def self.reset!
    self.config.reset
    @dispatcher_queue = nil
    @serializer       = nil
    @deserializer     = nil
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

  def self.push(queue_name, payload)
    @client.push(queue_name, payload)
  end

  def self.serialize(payload)
    @serializer.call(payload)
  end

  def self.deserialize(serialized_payload)
    @deserializer.call(serialized_payload)
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
    self.config.dispatcher_job_name
  end

  def self.published_events
    self.dispatcher_queue.published_events
  end

  class Config
    include NsOptions::Proxy

    option :dispatcher_name,     String, :default => 'dispatcher'
    option :dispatcher_job_name, String, :default => 'dispatch_event'

    option :serializer,   Proc, :default => proc{ |p| ::JSON.dump(p) }
    option :deserializer, Proc, :default => proc{ |p| ::JSON.load(p) }

    option :timeout, Float

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
  end

  module RedisUrl
    def self.new(ip, port, db)
      return if ip.to_s.empty? || port.to_s.empty? || db.to_s.empty?
      "redis://#{ip}:#{port}/#{db}"
    end
  end

end
