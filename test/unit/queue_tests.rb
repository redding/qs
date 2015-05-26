require 'assert'
require 'qs/queue'

require 'test/support/factory'

class Qs::Queue

  class UnitTests < Assert::Context
    desc "Qs::Queue"
    setup do
      @queue = Qs::Queue.new{ name Factory.string }
    end
    subject{ @queue }

    should have_readers :routes, :enqueued_jobs
    should have_imeths :name, :redis_key
    should have_imeths :job_handler_ns, :job
    should have_imeths :event_handler_ns, :event
    should have_imeths :enqueue, :add
    should have_imeths :published_events, :reset!

    should "default its routes to an empty array" do
      assert_equal [], subject.routes
    end

    should "default its enqueued jobs to an empty array" do
      assert_equal [], subject.enqueued_jobs
    end

    should "allow setting its name" do
      name = Factory.string
      subject.name name
      assert_equal name, subject.name
    end

    should "know its redis key" do
      result = subject.redis_key
      assert_equal RedisKey.new(subject.name), result
      assert_same result, subject.redis_key
    end

    should "not have a job handler ns by default" do
      assert_nil subject.job_handler_ns
    end

    should "allow setting its job handler ns" do
      namespace = Factory.string
      subject.job_handler_ns namespace
      assert_equal namespace, subject.job_handler_ns
    end

    should "not have an event handler ns by default" do
      assert_nil subject.event_handler_ns
    end

    should "allow setting its event handler ns" do
      namespace = Factory.string
      subject.event_handler_ns namespace
      assert_equal namespace, subject.event_handler_ns
    end

    should "allow adding job routes using `job`" do
      job_name     = Factory.string
      handler_name = Factory.string
      subject.job job_name, handler_name

      route = subject.routes.last
      assert_instance_of Qs::Route, route
      exp = Qs::Job::RouteName.new(Qs::Job::PAYLOAD_TYPE, job_name)
      assert_equal exp, route.name
      assert_equal handler_name, route.handler_class_name
    end

    should "use its job handler ns when adding job routes" do
      namespace = Factory.string
      subject.job_handler_ns namespace

      job_name     = Factory.string
      handler_name = Factory.string
      subject.job job_name, handler_name

      route = subject.routes.last
      exp = "#{namespace}::#{handler_name}"
      assert_equal exp, route.handler_class_name
    end

    should "not use its job handler ns with a top-level handler name" do
      namespace = Factory.string
      subject.job_handler_ns namespace

      job_name     = Factory.string
      handler_name = "::#{Factory.string}"
      subject.job job_name, handler_name

      route = subject.routes.last
      assert_equal handler_name, route.handler_class_name
    end

    should "allow adding event routes using `event`" do
      event_channel = Factory.string
      event_name    = Factory.string
      handler_name  = Factory.string
      subject.event event_channel, event_name, handler_name

      route = subject.routes.last
      assert_instance_of Qs::Route, route
      job_name = Qs::Event::JobName.new(event_channel, event_name)
      exp = Qs::Job::RouteName.new(Qs::Event::PAYLOAD_TYPE, job_name)
      assert_equal exp, route.name
      assert_equal handler_name, route.handler_class_name
    end

    should "use its event handler ns when adding event routes" do
      namespace = Factory.string
      subject.event_handler_ns namespace

      event_channel = Factory.string
      event_name    = Factory.string
      handler_name  = Factory.string
      subject.event event_channel, event_name, handler_name

      route = subject.routes.last
      exp = "#{namespace}::#{handler_name}"
      assert_equal exp, route.handler_class_name
    end

    should "not use its event handler ns with a top-level handler name" do
      namespace = Factory.string
      subject.event_handler_ns namespace

      event_channel = Factory.string
      event_name    = Factory.string
      handler_name  = "::#{Factory.string}"
      subject.event event_channel, event_name, handler_name

      route = subject.routes.last
      assert_equal handler_name, route.handler_class_name
    end

    should "return the enqueued jobs events using `published_events`" do
      dispatch_jobs = Factory.integer(3).times.map do
        Factory.dispatch_job.tap{ |j| subject.enqueued_jobs << j }
      end
      assert_equal dispatch_jobs.map(&:event), subject.published_events
    end

    should "clear its enqueued jobs when reset" do
      Factory.integer(3).times.map{ subject.enqueued_jobs << Factory.job }
      assert_not_empty subject.enqueued_jobs
      subject.reset!
      assert_empty subject.enqueued_jobs
    end

    should "know its custom inspect" do
      reference = '0x0%x' % (subject.object_id << 1)
      expected = "#<#{subject.class}:#{reference} " \
                   "@name=#{subject.name.inspect} " \
                   "@job_handler_ns=#{subject.job_handler_ns.inspect} " \
                   "@event_handler_ns=#{subject.event_handler_ns.inspect}>"
      assert_equal expected, subject.inspect
    end

    should "require a name when initialized" do
      assert_raises(InvalidError){ Qs::Queue.new }
    end

  end

  class EnqueueTests < UnitTests
    setup do
      @enqueue_args = nil
      Assert.stub(Qs, :enqueue){ |*args| @enqueue_args = args }

      @job_name   = Factory.string
      @job_params = { Factory.string => Factory.string }
    end

    should "add jobs using `enqueue`" do
      result = subject.enqueue(@job_name, @job_params)
      exp = [subject, @job_name, @job_params]
      assert_equal exp, @enqueue_args
      assert_equal @enqueue_args, result
    end

    should "add jobs using `add`" do
      result = subject.add(@job_name, @job_params)
      exp = [subject, @job_name, @job_params]
      assert_equal exp, @enqueue_args
      assert_equal @enqueue_args, result
    end

  end

  class RedisKeyTests < UnitTests
    desc "RedisKey"
    subject{ RedisKey }

    should have_imeths :parse_name, :new

    should "know how to build a redis key" do
      assert_equal "queues:#{@queue.name}", subject.new(@queue.name)
    end

    should "know how to parse a queue name from a key" do
      redis_key = subject.new(@queue.name)
      assert_equal @queue.name, subject.parse_name(redis_key)
    end

  end

end
