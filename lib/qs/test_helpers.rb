require 'qs/job'
require 'qs/event'
require 'qs/runner'

module Qs

  module TestHelpers

    # `module_function` makes every method a private instance method and a
    # public class method. Thus, the module can either be used directly or
    # included on a class.

    module_function

    # TODO: enqueued_jobs
    # def enqueued_jobs(queue)
    #   Qs.redis.lrange("queue:#{queue.redis_key}", 0, -1).map do |job_data|
    #     queue.decode_job_data(job_data)
    #   end
    # end

    # TODO: published_events
    # def published_events
    #   self.enqueued_jobs(distributor.queue).map do |job|
    #     Qs::Event.from_job(job)
    #   end
    # end

    # TODO: assert_job_enqueued(args=nil)
    # TODO: assert_event_published
    # def assert_event_published(channel, event, args=nil)
    #   last_event = self.published_events.last

    #   assert last_event
    #   assert_equal channel, last_event.channel
    #   assert_equal event,   last_event.name
    #   assert_equal args,    last_event.args

    #   distributor.tap do |distributor|
    #     event_job = last_event.to_job
    #     assert_equal distributor.queue_class,   event_job.queue_class
    #     assert_equal distributor.handler_class, event_job.handler_class
    #   end
    # end

    # TODO: clear_queue
    # def clear_queue(queue)
    #   queue.clear
    # end

    # TODO: clear_events_queue
    # def clear_events_queue
    #   self.clear_queue(distributor.queue)
    # end

    # TODO: run_queue
    # def run_queue(queue, &block)
    #   queue.test_worker.run(&block)
    # end

    # TODO: run_event_queue
    # def run_event_queue(queue, &block)
    #   self.run_queue(distributor.queue) do
    #     self.run_queue(queue, &block) # we must go deeper
    #   end
    # end

    def job_test_runner(*args)
      JobTestRunner.new(*args).tap{ |runner| runner.init }
    end

    def event_test_runner(*args)
      EventTestRunner.new(*args).tap{ |runner| runner.init }
    end

  end

  class JobTestRunner
    include Runner::TimeoutMethods
    attr_reader :handler_class, :job, :handler

    def initialize(handler_class, args=nil)
      @handler_class = handler_class
      @job = args.kind_of?(Job) ? args : Job.new(handler_class.to_s, args || {})
      @handler = @handler_class.new(@job.handler_args, @job)
    end

    def init
      timeout_after(@handler.timeout, 'init') { @handler.init }
    end

    def run
      timeout_after(@handler.timeout, 'run')  { @handler.run  }
    end

  end

  class EventTestRunner
    include Runner::TimeoutMethods
    attr_reader :handler_class, :event, :handler

    def initialize(handler_class, *args)
      @handler_class = handler_class
      @event = args.first.kind_of?(Event) ? args.first : Event.new(*args)
      @handler = @handler_class.new(@event.args, @event.to_job)
    end

    def init
      timeout_after(@handler.timeout, 'init') { @handler.init }
    end

    def run
      timeout_after(@handler.timeout, 'run')  { @handler.run  }
    end

  end

end
