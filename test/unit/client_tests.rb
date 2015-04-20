require 'assert'
require 'qs/client'

require 'hella-redis/connection_spy'
require 'qs/job'
require 'qs/queue'

module Qs::Client

  class UnitTests < Assert::Context
    desc "Qs::Client"
    setup do
      @current_test_mode = ENV['QS_TEST_MODE']
      ENV['QS_TEST_MODE'] = 'yes'

      @redis_config = Qs.redis_config
      @queue = Qs::Queue.new{ name Factory.string }
      @job   = Qs::Job.new(Factory.string, Factory.string => Factory.string)

      # the default JSON is not deterministic (key-values appear in different
      # order in the JSON string) which causes tests to randomly fail, this
      # fixes it for testing
      Assert.stub(Qs, :serialize){ |value| value.to_a.sort }
    end
    teardown do
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
      @client_class = Class.new do
        include Qs::Client
      end
      @client = @client_class.new(@redis_config)
    end
    subject{ @client }

    should have_readers :redis_config, :redis
    should have_imeths :enqueue, :append, :prepend

    should "know its redis config" do
      assert_equal @redis_config, subject.redis_config
    end

    should "not have a redis connection" do
      assert_nil subject.redis
    end

  end

  class AppendPrependTests < MixinTests
    setup do
      @connection_spy = HellaRedis::ConnectionSpy.new(@client.redis_config)
      Assert.stub(@client, :redis){ @connection_spy }

      @queue_redis_key    = Factory.string
      @serialized_payload = Factory.string
    end

    should "add a serialized payload to the end of a list using `append`" do
      subject.append(@queue_redis_key, @serialized_payload)

      call = @connection_spy.redis_calls.last
      assert_equal :lpush,              call.command
      assert_equal @queue_redis_key,    call.args.first
      assert_equal @serialized_payload, call.args.last
    end

    should "add a serialized payload to the front of a list using `prepend`" do
      subject.prepend(@queue_redis_key, @serialized_payload)

      call = @connection_spy.redis_calls.last
      assert_equal :rpush,              call.command
      assert_equal @queue_redis_key,    call.args.first
      assert_equal @serialized_payload, call.args.last
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

    should "add jobs to the queue's redis list using `enqueue`" do
      subject.enqueue(@queue, @job.name, @job.params)

      call = @connection_spy.redis_calls.last
      assert_equal :lpush, call.command
      assert_equal @queue.redis_key, call.args.first
      assert_equal Qs.serialize(@job.to_payload), call.args.last
    end

    should "default the job's params to an empty hash using `enqueue`" do
      subject.enqueue(@queue, @job.name)

      call = @connection_spy.redis_calls.last
      assert_equal :lpush, call.command
      exp = @job.to_payload.merge('params' => {})
      assert_equal Qs.serialize(exp), call.args.last
    end

    should "return the job when enqueuing" do
      result = subject.enqueue(@queue, @job.name, @job.params)
      assert_equal @job, result
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
      @client = @client_class.new(@redis_config)
    end
    subject{ @client }

    should "build a redis connection spy" do
      assert_instance_of HellaRedis::ConnectionSpy, subject.redis
      assert_equal @redis_config, subject.redis.config
    end

    should "track all the jobs it enqueues on the queue" do
      assert_empty @queue.enqueued_jobs
      result = subject.enqueue(@queue, @job.name, @job.params)

      job = @queue.enqueued_jobs.last
      assert_equal @job, job
      assert_equal @job, result
    end

  end

end
