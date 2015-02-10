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
    should have_imeths :enqueue, :client, :redis, :redis_config

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

    should "build a client" do
      assert_equal @client_spy,          subject.client
      assert_equal @client_spy.redis,    subject.redis
      assert_equal subject.redis_config, @client_spy.redis_config
    end

    should "call enqueue on its client using `enqueue`" do
      queue  = Qs::Queue.new{ name Factory.string }
      args   = [queue, Factory.string, { Factory.string => Factory.string }]
      result = subject.enqueue(*args)
      assert_equal args, result
    end

    should "reset its config, client and redis connection using `reset!`" do
      subject.reset!
      assert_nil subject.config.redis.url
      assert_nil subject.client
      assert_nil subject.redis
    end

  end

  class ConfigTests < UnitTests
    include NsOptions::AssertMacros

    desc "Config"
    setup do
      @config = Config.new
    end
    subject{ @config }

    should have_namespace :redis

    should "know its redis options" do
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

    def initialize(redis_confg)
      @redis_config  = redis_confg
      @redis         = Factory.string
    end

    def enqueue(queue, job_name, params = nil)
      [queue, job_name, params]
    end
  end

end
