require 'hella-redis'
require 'qs'
require 'qs/job'

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

    end

  end

  class QsClient
    include Client

    def initialize(*args)
      super
      @redis = HellaRedis::Connection.new(self.redis_config)
    end

    private

    def enqueue!(queue, job)
      serialized_payload = Qs.serialize(job.to_payload)
      self.redis.with{ |c| c.lpush(queue.redis_key, serialized_payload) }
    end

  end

  class TestClient
    include Client

    def initialize(*args)
      super
      require 'hella-redis/connection_spy'
      @redis = HellaRedis::ConnectionSpy.new(self.redis_config)
    end

    private

    def enqueue!(queue, job)
      queue.enqueued_jobs << job
    end

  end

end
