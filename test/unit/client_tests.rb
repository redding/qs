require 'assert'
require 'qs/client'

require 'hella-redis/connection_spy'
require 'qs'
require 'qs/job'
require 'qs/queue'

module Qs::Client

  class UnitTests < Assert::Context
    desc "Qs::Client"
    setup do
      @current_test_mode = ENV['QS_TEST_MODE']
      ENV['QS_TEST_MODE'] = 'yes'
      Qs.init

      @redis_config = Qs.redis_config
      @queue        = Qs::Queue.new{ name Factory.string }
      @job_name     = Factory.string
      @job_params   = { Factory.string => Factory.string }
    end
    teardown do
      Qs.reset!
      ENV['QS_TEST_MODE'] = @current_test_mode
    end
    subject{ Qs::Client }

    should have_imeths :new

    should "return a qs client using `new`" do
      ENV.delete('QS_TEST_MODE')
      client = subject.new(@redis_config)
      assert_instance_of Qs::QsClient, client
    end

    should "return a test client using `new` in test mode" do
      client = subject.new(@redis_config)
      assert_instance_of Qs::TestClient, client
    end

  end

  class MixinTests < UnitTests
    setup do
      @client = FakeClient.new(@redis_config)
    end
    subject{ @client }

    should have_readers :redis_config, :redis
    should have_imeths :enqueue, :publish, :publish_as, :push
    should have_imeths :block_dequeue
    should have_imeths :append, :prepend
    should have_imeths :clear
    should have_imeths :sync_subscriptions, :clear_subscriptions
    should have_imeths :event_subscribers

    should "know its redis config" do
      assert_equal @redis_config, subject.redis_config
    end

    should "not have a redis connection" do
      assert_nil subject.redis
    end

    should "build a job, enqueue it and return it using `enqueue`" do
      result = subject.enqueue(@queue, @job_name, @job_params)
      call = subject.enqueue_calls.last
      assert_equal @queue,      call.queue
      assert_equal @job_name,   call.job.name
      assert_equal @job_params, call.job.params
      assert_equal call.job,    result
    end

    should "enqueue a dispatch job and return its event using `publish`" do
      event_channel = Factory.string
      event_name    = Factory.string
      event_params  = @job_params
      result = subject.publish(event_channel, event_name, event_params)

      call = subject.enqueue_calls.last
      assert_equal Qs.dispatcher_queue, call.queue

      dispatch_job = Factory.dispatch_job({
        :event_channel => event_channel,
        :event_name    => event_name,
        :event_params  => event_params
      })
      assert_equal dispatch_job.name,   call.job.name
      assert_equal dispatch_job.params, call.job.params
      assert_equal call.job.event,      result
    end

    should "enqueue a dispatch job with a custom publisher using `publish_as`" do
      publisher = Factory.string
      channel   = Factory.string
      name      = Factory.string
      params    = @job_params
      result = subject.publish_as(publisher, channel, name, params)

      call = subject.enqueue_calls.last
      assert_equal Qs.dispatcher_queue, call.queue

      dispatch_job = Factory.dispatch_job({
        :event_channel   => channel,
        :event_name      => name,
        :event_params    => params,
        :event_publisher => publisher
      })
      assert_equal dispatch_job.name,   call.job.name
      assert_equal dispatch_job.params, call.job.params
      assert_equal call.job.event,      result
    end

    should "raise a not implemented error using `push`" do
      assert_raises(NotImplementedError) do
        subject.push(Factory.string, Factory.string)
      end
    end

  end

  class RedisCallTests < MixinTests
    setup do
      @connection_spy = HellaRedis::ConnectionSpy.new(@client.redis_config)
      Assert.stub(@client, :redis){ @connection_spy }

      @queue_redis_key = Factory.string
      @encoded_payload = Factory.string
    end

    should "block pop from the front of a list using `block_dequeue`" do
      args = (1..Factory.integer(3)).map{ Factory.string } + [Factory.integer]
      subject.block_dequeue(*args)

      call = @connection_spy.redis_calls.last
      assert_equal :brpop, call.command
      assert_equal args,   call.args
    end

    should "add a encoded payload to the end of a list using `append`" do
      subject.append(@queue_redis_key, @encoded_payload)

      call = @connection_spy.redis_calls.last
      assert_equal :lpush,           call.command
      assert_equal @queue_redis_key, call.args.first
      assert_equal @encoded_payload, call.args.last
    end

    should "add a encoded payload to the front of a list using `prepend`" do
      subject.prepend(@queue_redis_key, @encoded_payload)

      call = @connection_spy.redis_calls.last
      assert_equal :rpush,           call.command
      assert_equal @queue_redis_key, call.args.first
      assert_equal @encoded_payload, call.args.last
    end

    should "del a list using `clear`" do
      subject.clear(@queue_redis_key)

      call = @connection_spy.redis_calls.last
      assert_equal :del,               call.command
      assert_equal [@queue_redis_key], call.args
    end

    should "ping redis using `ping`" do
      subject.ping

      call = @connection_spy.redis_calls.last
      assert_equal :ping, call.command
    end

    should "return the events subscriber set using `event_subscribers`" do
      smembers_key = nil
      smembers = Factory.integer(3).times.map{ Factory.string }
      Assert.stub(@connection_spy.redis_spy, :smembers) do |key|
        smembers_key = key
        smembers
      end

      event = Factory.event
      result = subject.event_subscribers(event)

      assert_equal event.subscribers_redis_key, smembers_key
      assert_equal smembers, result
    end

  end

  class SubscriptionsSetupTests < RedisCallTests
    setup do
      @event_subs_keys = Factory.integer(3).times.map{ Factory.string }
      @keys_pattern = nil
      Assert.stub(@connection_spy.redis_spy, :keys) do |pattern|
        @keys_pattern = pattern
        @event_subs_keys
      end
    end

  end

  class SyncSubscriptionsTests < SubscriptionsSetupTests
    desc "sync_subscriptions"
    setup do
      Factory.integer(3).times.map{ @queue.event_route_names << Factory.string }
      subject.sync_subscriptions(@queue)
    end

    should "run in a pipelined transaction" do
      calls = @connection_spy.redis_calls[0, 2]
      assert_equal [:pipelined, :multi], calls.map(&:command)
    end

    should "find all event subscribers keys" do
      assert_equal Qs::Event::SubscribersRedisKey.new('*'), @keys_pattern
    end

    should "remove the queue from all events subscribers first" do
      calls = @connection_spy.redis_calls[2, @event_subs_keys.size]
      assert_equal @event_subs_keys.size, calls.size
      assert_equal [:srem], calls.map(&:command).uniq
      exp = @event_subs_keys.map{ |key| [key, @queue.name] }
      assert_equal exp, calls.map(&:args)
    end

    should "remove and add the queue from events subscribers" do
      start_at = 2 + @event_subs_keys.size
      calls = @connection_spy.redis_calls[start_at..-1]
      exp = @queue.event_route_names.size
      assert_equal exp, calls.size
      assert_equal [:sadd], calls.map(&:command).uniq
      exp = @queue.event_route_names.map do |name|
        [Qs::Event::SubscribersRedisKey.new(name), @queue.name]
      end
      assert_equal exp, calls.map(&:args)
    end

  end

  class ClearSubscriptionsTests < SubscriptionsSetupTests
    desc "clear_subscriptions"
    setup do
      subject.clear_subscriptions(@queue)
    end

    should "run in a pipelined transaction" do
      calls = @connection_spy.redis_calls[0, 2]
      assert_equal [:pipelined, :multi], calls.map(&:command)
    end

    should "find all event subscribers keys" do
      assert_equal Qs::Event::SubscribersRedisKey.new('*'), @keys_pattern
    end

    should "remove the queue from all events subscribers" do
      calls = @connection_spy.redis_calls[2..-1]
      assert_equal @event_subs_keys.size, calls.size
      assert_equal [:srem], calls.map(&:command).uniq
      exp = @event_subs_keys.map{ |key| [key, @queue.name] }
      assert_equal exp, calls.map(&:args)
    end

  end

  class QsClientTests < UnitTests
    desc "QsClient"
    setup do
      @client_class = Qs::QsClient
    end
    subject{ @client_class }

    should "be a qs client" do
      assert_includes Qs::Client, subject
    end

  end

  class QsClientInitTests < QsClientTests
    desc "when init"
    setup do
      @connection_spy = nil
      Assert.stub(HellaRedis::Connection, :new) do |*args|
        @connection_spy = HellaRedis::ConnectionSpy.new(*args)
      end

      @client = @client_class.new(@redis_config)
    end
    subject{ @client }

    should "build a redis connection" do
      assert_not_nil @connection_spy
      assert_equal @connection_spy.config, subject.redis_config
      assert_equal @connection_spy, subject.redis
    end

    should "add jobs to the queues redis list using `enqueue`" do
      subject.enqueue(@queue, @job_name, @job_params)

      call = @connection_spy.redis_calls.last
      assert_equal :lpush, call.command
      assert_equal @queue.redis_key, call.args.first
      job = Qs::Payload.deserialize(call.args.last)
      assert_equal @job_name,   job.name
      assert_equal @job_params, job.params
    end

    should "add a payload hash to the queues redis list using `push`" do
      payload_hash = { Factory.string => Factory.string }
      subject.push(@queue.name, payload_hash)

      call = @connection_spy.redis_calls.last
      assert_equal :lpush, call.command
      assert_equal @queue.redis_key, call.args.first
      assert_equal Qs.encode(payload_hash), call.args.last
    end

  end

  class TestClientTests < UnitTests
    desc "TestClient"
    setup do
      @client_class = Qs::TestClient
    end
    subject{ @client_class }

    should "be a qs client" do
      assert_includes Qs::Client, subject
    end

  end

  class TestClientInitTests < TestClientTests
    desc "when init"
    setup do
      @encoded_hash = nil
      Assert.stub(Qs, :encode){ |hash| @encoded_hash = hash }
      @serialized_job = nil
      Assert.stub(Qs::Payload, :serialize){ |job| @serialized_job = job }

      @client = @client_class.new(@redis_config)
    end
    subject{ @client }

    should have_readers :pushed_items
    should have_imeths :reset!

    should "build a redis connection spy" do
      assert_instance_of HellaRedis::ConnectionSpy, subject.redis
      assert_equal @redis_config, subject.redis.config
    end

    should "default its pushed items" do
      assert_equal [], subject.pushed_items
    end

    should "track all the jobs it enqueues on the queue" do
      assert_empty @queue.enqueued_jobs
      result = subject.enqueue(@queue, @job_name, @job_params)

      job = @queue.enqueued_jobs.last
      assert_equal @job_name,   job.name
      assert_equal @job_params, job.params
      assert_equal job, result
    end

    should "serialize the job when enqueueing" do
      subject.enqueue(@queue, @job_name, @job_params)

      job = @queue.enqueued_jobs.last
      assert_equal job, @serialized_job
    end

    should "track all the payload hashes pushed onto a queue" do
      payload_hash = { Factory.string => Factory.string }
      subject.push(@queue.name, payload_hash)

      pushed_item = subject.pushed_items.last
      assert_instance_of Qs::TestClient::PushedItem, pushed_item
      assert_equal @queue.name,  pushed_item.queue_name
      assert_equal payload_hash, pushed_item.payload_hash
    end

    should "encode the payload hashes when pushing them onto a queue" do
      payload_hash = { Factory.string => Factory.string }
      subject.push(@queue.name, payload_hash)

      pushed_item = subject.pushed_items.last
      assert_equal pushed_item.payload_hash, @encoded_hash
    end

    should "clear its pushed items when reset" do
      payload_hash = { Factory.string => Factory.string }
      subject.push(@queue.name, payload_hash)
      assert_not_empty subject.pushed_items
      subject.reset!
      assert_empty subject.pushed_items
    end

  end

  class FakeClient
    include Qs::Client

    attr_reader :enqueue_calls

    def enqueue!(queue, job)
      @enqueue_calls ||= []
      EnqueueCall.new(queue, job).tap{ |c| @enqueue_calls << c }
    end

    EnqueueCall = Struct.new(:queue, :job)
  end

end
