require 'connection_pool'
require 'redis'
require 'redis-namespace'

module Qs
  module RedisConnection

    def self.new(cfg)
      @pool = ::ConnectionPool.new(:timeout => cfg.timeout, :size => cfg.size) do
        ::Redis::Namespace.new(cfg.redis_ns, {
          :redis => ::Redis.connect({
            :url => cfg.url,
            :driver => cfg.driver
          })
        })
      end
    end

  end
end
