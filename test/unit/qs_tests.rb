require 'assert'
require 'qs'

require 'hella-redis/connection_spy'
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
    should have_imeths :event_subscribers
    should have_imeths :client, :redis, :redis_connect_hash
    should have_imeths :dispatcher_queue, :dispatcher_job_name
    should have_imeths :event_publisher
    should have_imeths :published_events

    should "know its config" do
      assert_instance_of Config, subject.config
    end

    should "configure its config" do
      yielded = nil
      subject.configure{ |c| yielded = c }
      assert_same subject.config, yielded
    end

    should "have a null client by default" do
      assert_instance_of NullClient, subject.client
    end

    should "not have a redis connection by default" do
      assert_nil subject.redis
    end

    should "know its redis config" do
      exp = subject.config.redis_connect_hash
      assert_equal exp, subject.redis_connect_hash
    end

  end

  class InitTests < UnitTests
    desc "when init"
    setup do
      @module.config.encoder    = proc{ |v| v.to_s }
      @module.config.decoder    = proc{ |v| v.to_i }
      @module.config.redis_ip   = Factory.string
      @module.config.redis_port = Factory.integer
      @module.config.redis_db   = Factory.integer

      @dispatcher_queue_spy = nil
      Assert.stub(DispatcherQueue, :new) do |*args|
        @dispatcher_queue_spy = DispatcherQueueSpy.new(*args)
      end

      @client_spy = nil
      Assert.stub(Client, :new) do |*args|
        @client_spy = ClientSpy.new(*args)
      end

      @module.init
    end

    should "validate its config" do
      assert_true subject.config.valid?
    end

    should "build a dispatcher queue" do
      assert_equal @dispatcher_queue_spy, subject.dispatcher_queue

      c   = subject.config
      spy = @dispatcher_queue_spy
      assert_equal c.dispatcher_queue_class,            spy.queue_class
      assert_equal c.dispatcher_queue_name,             spy.queue_name
      assert_equal c.dispatcher_job_name,               spy.job_name
      assert_equal c.dispatcher_job_handler_class_name, spy.job_handler_class_name
    end

    should "build a client" do
      assert_equal @client_spy,       subject.client
      assert_equal @client_spy.redis, subject.redis

      assert_equal subject.redis_connect_hash, @client_spy.redis_connect_hash
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
      assert_equal value.to_s, subject.encode(value)
    end

    should "use the configured decoder using `decode`" do
      value = Factory.integer.to_s
      assert_equal value.to_i, subject.decode(value)
    end

    should "demeter its clients subscription methods" do
      queue = Qs::Queue.new{ name Factory.string }

      subject.sync_subscriptions(queue)
      call = @client_spy.sync_subscriptions_calls.last
      assert_equal queue, call.queue

      subject.clear_subscriptions(queue)
      call = @client_spy.clear_subscriptions_calls.last
      assert_equal queue, call.queue
    end

    should "demeter its event publishers method to its client" do
      event = Factory.event
      subject.event_subscribers(event)

      call = @client_spy.event_subscribers_calls.last
      assert_equal event, call.event
    end

    should "know its dispatcher job name and event publisher" do
      exp = subject.config.dispatcher_job_name
      assert_equal exp, subject.dispatcher_job_name

      exp = subject.config.event_publisher
      assert_equal exp, subject.event_publisher
    end

    should "return the dispatcher queue published events using `published_events`" do
      exp = Factory.integer(3).times.map{ Factory.string }
      Assert.stub(subject.dispatcher_queue, :published_events){ exp }

      assert_equal exp, subject.published_events
    end

    should "not reset its attributes when init again" do
      config = subject.config
      queue  = subject.dispatcher_queue
      client = subject.client
      redis  = subject.redis
      subject.init

      assert_same config, subject.config
      assert_same queue,  subject.dispatcher_queue
      assert_same client, subject.client
      assert_same redis,  subject.redis
    end

    should "reset itself using `reset!`" do
      subject.reset!

      assert_false subject.config.valid?
      assert_nil subject.dispatcher_queue
      assert_nil subject.redis
      assert_instance_of NullClient, subject.client
      assert_raises(NoMethodError){ subject.encode(Factory.integer) }
      assert_raises(NoMethodError){ subject.decode(Factory.integer) }
    end

  end

  class ConfigTests < UnitTests
    desc "Config"
    setup do
      @config = Config.new
    end
    subject{ @config }

    should have_accessors :encoder, :decoder, :timeout, :event_publisher
    should have_accessors :dispatcher_queue_class, :dispatcher_queue_name
    should have_accessors :dispatcher_job_name, :dispatcher_job_handler_class_name
    should have_accessors :redis_ip, :redis_port, :redis_db, :redis_ns
    should have_accessors :redis_driver, :redis_timeout, :redis_size, :redis_url
    should have_imeths :redis_connect_hash, :valid?, :validate!

    should "know its default attr values" do
      payload = { Factory.string => Factory.string }

      exp = JSON.dump(payload)
      assert_equal exp, Config::DEFAULT_ENCODER.call(payload)

      encoded_payload = exp
      exp = JSON.load(encoded_payload)
      assert_equal exp, Config::DEFAULT_DECODER.call(encoded_payload)

      assert_equal Queue,              Config::DEFAULT_DISPATCHER_QUEUE_CLASS
      assert_equal 'dispatcher',       Config::DEFAULT_DISPATCHER_QUEUE_NAME
      assert_equal 'run_dispatch_job', Config::DEFAULT_DISPATCHER_JOB_NAME

      exp = DispatcherQueue::RunDispatchJob.to_s
      assert_equal exp, Config::DEFAULT_DISPATCHER_JOB_HANDLER_CLASS_NAME

      assert_equal '127.0.0.1', Config::DEFAULT_REDIS_IP
      assert_equal 6379,        Config::DEFAULT_REDIS_PORT
      assert_equal 0,           Config::DEFAULT_REDIS_DB
      assert_equal 'qs',        Config::DEFAULT_REDIS_NS
      assert_equal 'ruby',      Config::DEFAULT_REDIS_DRIVER
      assert_equal 1,           Config::DEFAULT_REDIS_TIMEOUT
      assert_equal 4,           Config::DEFAULT_REDIS_SIZE
    end

    should "default its attrs" do
      c = subject.class

      assert_equal c::DEFAULT_ENCODER, subject.encoder
      assert_equal c::DEFAULT_DECODER, subject.decoder

      assert_nil subject.timeout
      assert_nil subject.event_publisher

      assert_equal c::DEFAULT_DISPATCHER_QUEUE_CLASS, subject.dispatcher_queue_class
      assert_equal c::DEFAULT_DISPATCHER_QUEUE_NAME,  subject.dispatcher_queue_name
      assert_equal c::DEFAULT_DISPATCHER_JOB_NAME,    subject.dispatcher_job_name

      exp = c::DEFAULT_DISPATCHER_JOB_HANDLER_CLASS_NAME
      assert_equal exp, subject.dispatcher_job_handler_class_name

      assert_equal c::DEFAULT_REDIS_IP,      subject.redis_ip
      assert_equal c::DEFAULT_REDIS_PORT,    subject.redis_port
      assert_equal c::DEFAULT_REDIS_DB,      subject.redis_db
      assert_equal c::DEFAULT_REDIS_NS,      subject.redis_ns
      assert_equal c::DEFAULT_REDIS_DRIVER,  subject.redis_driver
      assert_equal c::DEFAULT_REDIS_TIMEOUT, subject.redis_timeout
      assert_equal c::DEFAULT_REDIS_SIZE,    subject.redis_size

      assert_nil subject.redis_url
    end

    should "know its redis connect hash" do
      exp = {
        :ip       => subject.redis_ip,
        :port     => subject.redis_port,
        :db       => subject.redis_db,
        :redis_ns => subject.redis_ns,
        :driver   => subject.redis_driver,
        :timeout  => subject.redis_timeout,
        :size     => subject.redis_size,
        :url      => subject.redis_url
      }
      assert_equal exp, subject.redis_connect_hash
    end

    should "not be valid until validate! has been called" do
      assert_false subject.valid?

      subject.validate!
      assert_true subject.valid?
    end

    should "set its redis url on validate!" do
      assert_nil subject.redis_url
      subject.validate!

      exp = RedisUrl.new(subject.redis_ip, subject.redis_port, subject.redis_db)
      assert_equal exp, subject.redis_url
    end

    should "only be able to be validated once" do
      subject.validate!

      exp = RedisUrl.new(subject.redis_ip, subject.redis_port, subject.redis_db)
      assert_equal exp, subject.redis_url

      new_ip = Factory.string
      subject.redis_ip = new_ip
      subject.validate!

      orig_exp = exp
      new_exp  = RedisUrl.new(new_ip, subject.redis_port, subject.redis_db)
      assert_not_equal new_exp, subject.redis_url
      assert_equal orig_exp, subject.redis_url
    end

  end

  class RedisUrlTests < UnitTests
    desc "RedisUrl"
    subject{ RedisUrl }

    should "build a redis url when passed an ip, port and db" do
      ip   = Factory.string
      port = Factory.integer
      db   = Factory.integer
      exp = "redis://#{ip}:#{port}/#{db}"
      assert_equal exp, subject.new(ip, port, db)
    end

    should "not return a url with an ip, port or db" do
      assert_nil subject.new(nil, Factory.integer, Factory.integer)
      assert_nil subject.new(Factory.string, nil, Factory.integer)
      assert_nil subject.new(Factory.string, Factory.integer, nil)
    end

  end

  class NullClientTests < UnitTests
    desc "NullClient"
    setup do
      @null_client = NullClient.new
    end
    subject{ @null_client }

    should have_imeths :enqueue, :publish, :publish_as, :push
    should have_imeths :sync_subscriptions, :clear_subscriptions
    should have_imeths :event_subscribers

    should "raise uninitialized errors" do
      queue      = Qs::Queue.new{ name Factory.string }
      job_name   = Factory.string
      job_params = { Factory.string => Factory.string }
      assert_raises(UninitializedError) do
        subject.enqueue(queue, job_name, job_params)
      end

      event_channel = Factory.string
      event_name    = Factory.string
      event_params  = { Factory.string => Factory.string }
      assert_raises(UninitializedError) do
        subject.publish(event_channel, event_name, event_params)
      end

      event_publisher = Factory.string
      assert_raises(UninitializedError) do
        subject.publish_as(event_publisher, event_channel, event_name, event_params)
      end

      payload = { Factory.string => Factory.string }
      assert_raises(UninitializedError){ subject.push(queue.name, payload) }

      assert_raises(UninitializedError){ subject.sync_subscriptions(queue) }
      assert_raises(UninitializedError){ subject.clear_subscriptions(queue) }

      event = Factory.event
      assert_raises(UninitializedError){ subject.event_subscribers(event) }
    end

  end

  class DispatcherQueueSpy
    attr_reader :queue_class, :queue_name
    attr_reader :job_name, :job_handler_class_name
    attr_reader :published_events

    def initialize(options)
      @queue_class            = options[:queue_class]
      @queue_name             = options[:queue_name]
      @job_name               = options[:job_name]
      @job_handler_class_name = options[:job_handler_class_name]
    end
  end

  class ClientSpy
    attr_reader :redis_connect_hash, :redis
    attr_reader :enqueue_calls, :publish_calls, :push_calls
    attr_reader :sync_subscriptions_calls, :clear_subscriptions_calls
    attr_reader :event_subscribers_calls

    def initialize(redis_confg)
      @redis_connect_hash = redis_confg
      @redis              = Factory.string
      @enqueue_calls      = []
      @publish_calls      = []
      @push_calls         = []
      @sync_subscriptions_calls  = []
      @clear_subscriptions_calls = []
      @event_subscribers_calls   = []
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
      @sync_subscriptions_calls << SubscriptionsCall.new(queue)
    end

    def clear_subscriptions(queue)
      @clear_subscriptions_calls << SubscriptionsCall.new(queue)
    end

    def event_subscribers(event)
      @event_subscribers_calls << SubscribersCall.new(event)
    end

    EnqueueCall       = Struct.new(:queue, :job_name, :job_params)
    PublishCall       = Struct.new(:event_channel, :event_name, :event_params, :event_publisher)
    PushCall          = Struct.new(:queue_name, :payload)
    SubscriptionsCall = Struct.new(:queue, :event_job_names)
    SubscribersCall   = Struct.new(:event)
  end

end
