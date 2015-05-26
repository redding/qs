require 'qs/route'

module Qs

  class Queue

    attr_reader :routes
    attr_reader :enqueued_jobs

    def initialize(&block)
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

    def event_handler_ns(value = nil)
      @event_handler_ns = value if !value.nil?
      @event_handler_ns
    end

    def job(name, handler_name)
      if self.job_handler_ns && !(handler_name =~ /^::/)
        handler_name = "#{self.job_handler_ns}::#{handler_name}"
      end

      route_name = Qs::Job::RouteName.new(Qs::Job::PAYLOAD_TYPE, name)
      @routes.push(Qs::Route.new(route_name, handler_name))
    end

    def event(channel, name, handler_name)
      if self.event_handler_ns && !(handler_name =~ /^::/)
        handler_name = "#{self.event_handler_ns}::#{handler_name}"
      end

      job_name   = Qs::Event::JobName.new(channel, name)
      route_name = Qs::Job::RouteName.new(Qs::Event::PAYLOAD_TYPE, job_name)
      @routes.push(Qs::Route.new(route_name, handler_name))
    end

    def enqueue(job_name, params = nil)
      Qs.enqueue(self, job_name, params)
    end
    alias :add :enqueue

    def published_events
      self.enqueued_jobs.map(&:event)
    end

    def reset!
      self.enqueued_jobs.clear
    end

    def inspect
      reference = '0x0%x' % (self.object_id << 1)
      "#<#{self.class}:#{reference} " \
        "@name=#{self.name.inspect} " \
        "@job_handler_ns=#{self.job_handler_ns.inspect} " \
        "@event_handler_ns=#{self.event_handler_ns.inspect}>"
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
