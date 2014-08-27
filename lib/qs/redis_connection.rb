require 'hella-redis'

module Qs

  module RedisConnection

    def self.new(options)
      config = Config.new(options)
      HellaRedis::RedisConnection.new(config)
    end

    class Config
      attr_reader :url, :redis_ns
      attr_reader :driver
      attr_reader :timeout, :size

      def initialize(options)
        @url      = options[:url]
        @redis_ns = options[:redis_ns]
        @driver   = options[:driver]
        @timeout  = options[:timeout]
        @size     = options[:size]
      end
    end

  end

end
