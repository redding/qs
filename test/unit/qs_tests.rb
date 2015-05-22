require 'assert'
require 'qs'

require 'hella-redis/connection_spy'
require 'ns-options/assert_macros'
require 'qs/job'
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
    should have_imeths :enqueue, :push
    should have_imeths :serialize, :deserialize
    should have_imeths :client, :redis, :redis_config
    should have_imeths :dispatcher_queue, :dispatcher_job_name

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
      @module.config.serializer   = proc{ |v| v.to_s }
      @module.config.deserializer = proc{ |v| v.to_i }
      @module.config.redis.ip     = Factory.string
      @module.config.redis.port   = Factory.integer
      @module.config.redis.db     = Factory.integer

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

    should "know its dispatcher queue and dispatcher job name" do
      assert_instance_of Qs::Queue, subject.dispatcher_queue
      exp = subject.config.dispatcher_name
      assert_equal exp, subject.dispatcher_queue.name
      exp = subject.config.dispatcher_job_name
      assert_equal exp, subject.dispatcher_job_name
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

    should "call push on its client using `push`" do
      queue_name = Factory.string
      payload    = { Factory.string => Factory.string }
      subject.push(queue_name, payload)

      call = @client_spy.push_calls.last
      assert_equal queue_name, call.queue_name
      assert_equal payload,    call.payload
    end

    should "use the configured serializer using `serialize`" do
      value = Factory.integer
      result = subject.serialize(value)
      assert_equal value.to_s, result
    end

    should "use the configured deserializer using `deserialize`" do
      value = Factory.integer.to_s
      result = subject.deserialize(value)
      assert_equal value.to_i, result
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
      assert_raises(NoMethodError){ subject.serialize(Factory.integer) }
      assert_raises(NoMethodError){ subject.deserialize(Factory.integer) }
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
    should have_options :serializer, :deserializer, :timeout
    should have_namespace :redis

    should "know its default dispatcher name and job name" do
      assert_equal 'dispatcher',     subject.dispatcher_name
      assert_equal 'dispatch_event', subject.dispatcher_job_name
    end

    should "know its default serializer/deserializer" do
      payload = { Factory.string => Factory.string }

      exp = JSON.dump(payload)
      serialized_payload = subject.serializer.call(payload)
      assert_equal exp, serialized_payload
      exp = JSON.load(exp)
      assert_equal exp, subject.deserializer.call(serialized_payload)
    end

    should "know its default timeout" do
      assert_nil subject.timeout
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
    attr_reader :enqueue_calls, :push_calls

    def initialize(redis_confg)
      @redis_config  = redis_confg
      @redis         = Factory.string
      @enqueue_calls = []
      @push_calls    = []
    end

    def enqueue(queue, job_name, job_params = nil)
      @enqueue_calls << EnqueueCall.new(queue, job_name, job_params)
    end

    def push(queue_name, payload)
      @push_calls << PushCall.new(queue_name, payload)
    end

    EnqueueCall = Struct.new(:queue, :job_name, :job_params)
    PushCall    = Struct.new(:queue_name, :payload)
  end

end
