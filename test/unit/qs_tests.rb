require 'assert'
require 'qs'

require 'hella-redis/connection_spy'
require 'ns-options/assert_macros'
require 'qs/queue'

module Qs

  class UnitTests < Assert::Context
    desc "Qs"
    setup do
      Qs.reset!
      @module = Qs
    end
    teardown do
      Qs.reset!
      Qs.init
    end
    subject{ @module }

    should have_imeths :config, :configure, :init, :reset!
    should have_imeths :enqueue, :publish, :publish_as, :push
    should have_imeths :encode, :decode
    should have_imeths :sync_subscriptions, :clear_subscriptions
    should have_imeths :client, :redis, :redis_config
    should have_imeths :dispatcher_queue, :dispatcher_job_name
    should have_imeths :event_publisher
    should have_imeths :published_events

    should "know its config" do
      assert_instance_of Config, subject.config
    end

    should "allow configuring its config" do
      yielded = nil
      subject.configure{ |c| yielded = c }
      assert_equal subject.config, yielded
    end

    should "not have a client or redis connection by default" do
      assert_nil subject.client
      assert_nil subject.redis
    end

    should "know its redis config" do
      expected = subject.config.redis.to_hash
      assert_equal expected, subject.redis_config
    end

  end

  class InitTests < UnitTests
    desc "when init"
    setup do
      @module.config.encoder    = proc{ |v| v.to_s }
      @module.config.decoder    = proc{ |v| v.to_i }
      @module.config.redis.ip   = Factory.string
      @module.config.redis.port = Factory.integer
      @module.config.redis.db   = Factory.integer

      @client_spy = nil
      Assert.stub(Client, :new) do |*args|
        @client_spy = ClientSpy.new(*args)
      end

      @module.init
    end

    should "set its configured redis url" do
      expected = RedisUrl.new(
        subject.config.redis.ip,
        subject.config.redis.port,
        subject.config.redis.db
      )
      assert_equal expected, subject.config.redis.url
    end

    should "know its dispatcher queue, dispatcher job name and event publisher" do
      assert_instance_of Qs::Queue, subject.dispatcher_queue
      exp = subject.config.dispatcher_name
      assert_equal exp, subject.dispatcher_queue.name
      exp = subject.config.dispatcher_job_name
      assert_equal exp, subject.dispatcher_job_name
      exp = subject.config.event_publisher
      assert_equal exp, subject.event_publisher
    end

    should "build a client" do
      assert_equal @client_spy,          subject.client
      assert_equal @client_spy.redis,    subject.redis
      assert_equal subject.redis_config, @client_spy.redis_config
    end

    should "call enqueue on its client using `enqueue`" do
      queue      = Qs::Queue.new{ name Factory.string }
      job_name   = Factory.string
      job_params = { Factory.string => Factory.string }
      subject.enqueue(queue, job_name, job_params)

      call = @client_spy.enqueue_calls.last
      assert_equal queue,      call.queue
      assert_equal job_name,   call.job_name
      assert_equal job_params, call.job_params
    end

    should "call publish on its client using `publish`" do
      event_channel = Factory.string
      event_name    = Factory.string
      event_params  = { Factory.string => Factory.string }
      subject.publish(event_channel, event_name, event_params)

      call = @client_spy.publish_calls.last
      assert_equal event_channel, call.event_channel
      assert_equal event_name,    call.event_name
      assert_equal event_params,  call.event_params
    end

    should "call publish as on its client using `publish_as`" do
      event_publisher = Factory.string
      event_channel   = Factory.string
      event_name      = Factory.string
      event_params    = { Factory.string => Factory.string }
      subject.publish_as(event_publisher, event_channel, event_name, event_params)

      call = @client_spy.publish_calls.last
      assert_equal event_publisher, call.event_publisher
      assert_equal event_channel,   call.event_channel
      assert_equal event_name,      call.event_name
      assert_equal event_params,    call.event_params
    end

    should "call push on its client using `push`" do
      queue_name = Factory.string
      payload    = { Factory.string => Factory.string }
      subject.push(queue_name, payload)

      call = @client_spy.push_calls.last
      assert_equal queue_name, call.queue_name
      assert_equal payload,    call.payload
    end

    should "use the configured encoder using `encode`" do
      value = Factory.integer
      result = subject.encode(value)
      assert_equal value.to_s, result
    end

    should "use the configured decoder using `decode`" do
      value = Factory.integer.to_s
      result = subject.decode(value)
      assert_equal value.to_i, result
    end

    should "demete its clients subscription methods" do
      queue = Qs::Queue.new{ name Factory.string }

      subject.sync_subscriptions(queue)
      call = @client_spy.sync_subscriptions_calls.last
      assert_equal queue, call.queue

      subject.clear_subscriptions(queue)
      call = @client_spy.clear_subscriptions_calls.last
      assert_equal queue, call.queue
    end

    should "return the dispatcher queue published events using `published_events`" do
      queue = subject.dispatcher_queue
      published_events = Factory.integer(3).times.map{ Factory.string }
      Assert.stub(queue, :published_events){ published_events }
      assert_equal queue.published_events, subject.published_events
    end

    should "not reset its attributes when init again" do
      queue  = subject.dispatcher_queue
      client = subject.client
      redis  = subject.redis
      subject.init
      assert_same queue,  subject.dispatcher_queue
      assert_same client, subject.client
      assert_same redis,  subject.redis
    end

    should "reset itself using `reset!`" do
      subject.reset!
      assert_nil subject.config.redis.url
      assert_nil subject.dispatcher_queue
      assert_nil subject.client
      assert_nil subject.redis
      assert_raises(NoMethodError){ subject.encode(Factory.integer) }
      assert_raises(NoMethodError){ subject.decode(Factory.integer) }
    end

  end

  class ConfigTests < UnitTests
    include NsOptions::AssertMacros

    desc "Config"
    setup do
      @config = Config.new
    end
    subject{ @config }

    should have_options :dispatcher_name, :dispatcher_job_name
    should have_options :encoder, :decoder, :timeout
    should have_options :event_publisher
    should have_namespace :redis

    should "know its default dispatcher name and job name" do
      assert_equal 'dispatcher',     subject.dispatcher_name
      assert_equal 'dispatch_event', subject.dispatcher_job_name
    end

    should "know its default decoder/encoder" do
      payload = { Factory.string => Factory.string }

      exp = JSON.dump(payload)
      encoded_payload = subject.encoder.call(payload)
      assert_equal exp, encoded_payload
      exp = JSON.load(exp)
      assert_equal exp, subject.decoder.call(encoded_payload)
    end

    should "know its default timeout" do
      assert_nil subject.timeout
    end

    should "not have a default event publisher" do
      assert_nil subject.event_publisher
    end

    should "know its default redis options" do
      assert_equal 'localhost', subject.redis.ip
      assert_equal 6379,        subject.redis.port
      assert_equal 0,           subject.redis.db
      assert_equal 'qs',        subject.redis.redis_ns
      assert_equal 'ruby',      subject.redis.driver
      assert_equal 1,           subject.redis.timeout
      assert_equal 4,           subject.redis.size
      assert_nil subject.redis.url
    end

  end

  class RedisUrlTests < UnitTests
    desc "RedisUrl"
    subject{ RedisUrl }

    should "build a redis url when passed an ip, port and db" do
      ip   = Factory.string
      port = Factory.integer
      db   = Factory.integer
      expected = "redis://#{ip}:#{port}/#{db}"
      assert_equal expected, subject.new(ip, port, db)
    end

    should "not return a url with an ip, port or db" do
      assert_nil subject.new(nil, Factory.integer, Factory.integer)
      assert_nil subject.new(Factory.string, nil, Factory.integer)
      assert_nil subject.new(Factory.string, Factory.integer, nil)
    end

  end

  class ClientSpy
    attr_reader :redis_config, :redis
    attr_reader :enqueue_calls, :publish_calls, :push_calls
    attr_reader :sync_subscriptions_calls, :clear_subscriptions_calls

    def initialize(redis_confg)
      @redis_config  = redis_confg
      @redis         = Factory.string
      @enqueue_calls = []
      @publish_calls = []
      @push_calls    = []
      @read_subscriptions_calls  = []
      @sync_subscriptions_calls  = []
      @clear_subscriptions_calls = []
    end

    def enqueue(queue, name, params = nil)
      @enqueue_calls << EnqueueCall.new(queue, name, params)
    end

    def publish(channel, name, params = nil)
      @publish_calls << PublishCall.new(channel, name, params)
    end

    def publish_as(publisher, channel, name, params = nil)
      @publish_calls << PublishCall.new(channel, name, params, publisher)
    end

    def push(queue_name, payload)
      @push_calls << PushCall.new(queue_name, payload)
    end

    def sync_subscriptions(queue)
      @sync_subscriptions_calls << SubscriptionCall.new(queue)
    end

    def clear_subscriptions(queue)
      @clear_subscriptions_calls << SubscriptionCall.new(queue)
    end

    EnqueueCall      = Struct.new(:queue, :job_name, :job_params)
    PublishCall      = Struct.new(:event_channel, :event_name, :event_params, :event_publisher)
    PushCall         = Struct.new(:queue_name, :payload)
    SubscriptionCall = Struct.new(:queue, :event_job_names)
  end

end
