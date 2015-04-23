require 'hella-redis'
require 'qs'
require 'qs/job'
require 'qs/queue'

module Qs

  module Client

    def self.new(*args)
      if !ENV['QS_TEST_MODE']
        QsClient.new(*args)
      else
        TestClient.new(*args)
      end
    end

    def self.included(klass)
      klass.class_eval do
        include InstanceMethods
      end
    end

    module InstanceMethods

      attr_reader :redis_config, :redis

      def initialize(redis_config)
        @redis_config = redis_config
      end

      def enqueue(queue, job_name, params = nil)
        job = Qs::Job.new(job_name, params || {})
        enqueue!(queue, job)
        job
      end

      def push(queue_name, payload)
        raise NotImplementedError
      end

      def block_dequeue(*args)
        self.redis.with{ |c| c.brpop(*args) }
      end

      def append(queue_redis_key, serialized_payload)
        self.redis.with{ |c| c.lpush(queue_redis_key, serialized_payload) }
      end

      def prepend(queue_redis_key, serialized_payload)
        self.redis.with{ |c| c.rpush(queue_redis_key, serialized_payload) }
      end

      def clear(redis_key)
        self.redis.with{ |c| c.del(redis_key) }
      end

    end

  end

  class QsClient
    include Client

    def initialize(*args)
      super
      @redis = HellaRedis::Connection.new(self.redis_config)
    end

    def push(queue_name, payload)
      queue_redis_key    = Queue::RedisKey.new(queue_name)
      serialized_payload = Qs.serialize(payload)
      self.append(queue_redis_key, serialized_payload)
    end

    private

    def enqueue!(queue, job)
      serialized_payload = Qs.serialize(job.to_payload)
      self.append(queue.redis_key, serialized_payload)
    end

  end

  class TestClient
    include Client

    attr_reader :pushed_items

    def initialize(*args)
      super
      require 'hella-redis/connection_spy'
      @redis = HellaRedis::ConnectionSpy.new(self.redis_config)
      @pushed_items = []
    end

    def push(queue_name, payload)
      # attempt to serialize (and then throw away) the payload, this will error
      # on the developer if it can't be serialized
      Qs.serialize(payload)
      @pushed_items << PushedItem.new(queue_name, payload)
    end

    def reset!
      @pushed_items.clear
    end

    private

    def enqueue!(queue, job)
      # attempt to serialize (and then throw away) the job payload, this will
      # error on the developer if it can't serialize the job
      Qs.serialize(job.to_payload)
      queue.enqueued_jobs << job
    end

    PushedItem = Struct.new(:queue_name, :payload)

  end

end
