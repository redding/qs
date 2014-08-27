require 'ns-options'
require 'qs/version'
require 'qs/redis_connection'

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
    @redis = RedisConnection.new(self.redis_config)
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
