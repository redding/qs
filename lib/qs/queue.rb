require 'qs/route'

module Qs

  class Queue

    attr_reader :routes

    def initialize(&block)
      @job_handler_ns = nil
      @routes = []
      self.instance_eval(&block) if !block.nil?
      raise InvalidError, "a queue must have a name" if self.name.nil?
    end

    def name(value = nil)
      @name = value if !value.nil?
      @name
    end

    def redis_key
      "queues:#{@name}"
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

    def inspect
      reference = '0x0%x' % (self.object_id << 1)
      "#<#{self.class}:#{reference} " \
        "@name=#{self.name.inspect} " \
        "@job_handler_ns=#{self.job_handler_ns.inspect}>"
    end

    InvalidError = Class.new(RuntimeError)

  end

end
