require 'ns-options'
require 'qs/version'
require 'qs/client'
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
    @client = Client.new(self.redis_config)
    @redis  = @client.redis
    true
  end

  def self.reset!
    self.config.reset
    @client = nil
    @redis  = nil
    true
  end

  def self.enqueue(queue, job_name, params = nil)
    @client.enqueue(queue, job_name, params)
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

  class Config
    include NsOptions::Proxy

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
