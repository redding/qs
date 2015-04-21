require 'qs/route'

module Qs

  class Queue

    attr_reader :routes
    attr_reader :enqueued_jobs

    def initialize(&block)
      @job_handler_ns = nil
      @routes = []
      @enqueued_jobs = []
      self.instance_eval(&block) if !block.nil?
      raise InvalidError, "a queue must have a name" if self.name.nil?
    end

    def name(value = nil)
      @name = value if !value.nil?
      @name
    end

    def redis_key
      @redis_key ||= RedisKey.new(self.name)
    end

    def job_handler_ns(value = nil)
      @job_handler_ns = value if !value.nil?
      @job_handler_ns
    end

    def job(name, handler_name)
      if self.job_handler_ns && !(handler_name =~ /^::/)
        handler_name = "#{self.job_handler_ns}::#{handler_name}"
      end

      @routes.push(Qs::Route.new(name, handler_name))
    end

    def enqueue(job_name, params = nil)
      Qs.enqueue(self, job_name, params)
    end
    alias :add :enqueue

    def reset!
      self.enqueued_jobs.clear
    end

    def inspect
      reference = '0x0%x' % (self.object_id << 1)
      "#<#{self.class}:#{reference} " \
        "@name=#{self.name.inspect} " \
        "@job_handler_ns=#{self.job_handler_ns.inspect}>"
    end

    InvalidError = Class.new(RuntimeError)

    module RedisKey
      def self.parse_name(key)
        key.split(':').last
      end

      def self.new(name)
        "queues:#{name}"
      end
    end

  end

end
