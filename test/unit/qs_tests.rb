require 'assert'
require 'qs'

require 'hella-redis/connection_spy'
require 'ns-options/assert_macros'

module Qs

  class UnitTests < Assert::Context
    desc "Qs"
    setup do
      @current_config = Qs.config
      @current_redis  = Qs.redis
      Qs.instance_variable_set("@config", nil)
      Qs.instance_variable_set("@redis", nil)

      @module = Qs
    end
    teardown do
      Qs.instance_variable_set("@redis", @current_redis)
      Qs.instance_variable_set("@config", @current_config)
    end
    subject{ @module }

    should have_imeths :config, :configure, :init
    should have_imeths :redis, :redis_config

    should "know its config" do
      assert_instance_of Config, subject.config
    end

    should "allow configuring its config" do
      yielded = nil
      subject.configure{ |c| yielded = c }
      assert_equal subject.config, yielded
    end

    should "not have a redis connection by default" do
      assert_nil subject.redis
    end

    should "know its redis config" do
      expected = subject.config.redis.to_hash
      assert_equal expected, subject.redis_config
    end

    should "set its configured redis url when init" do
      subject.config.redis.ip   = Factory.string
      subject.config.redis.port = Factory.integer
      subject.config.redis.db   = Factory.integer
      subject.init

      expected = RedisUrl.new(
        subject.config.redis.ip,
        subject.config.redis.port,
        subject.config.redis.db
      )
      assert_equal expected, subject.config.redis.url
    end

  end

  class InitTests < UnitTests
    desc "when init"
    setup do
      @redis_spy = nil
      Assert.stub(HellaRedis::Connection, :new) do |*args|
        @redis_spy = HellaRedis::ConnectionSpy.new(*args)
      end

      @module.init
    end

    should "build a redis connection" do
      assert_equal @redis_spy,        subject.redis
      assert_equal @redis_spy.config, subject.redis_config
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
      assert_equal 6379, subject.redis.port
      assert_equal 0, subject.redis.db
      assert_nil subject.redis.url
      assert_equal 'qs', subject.redis.redis_ns
      assert_equal 'ruby', subject.redis.driver
      assert_equal 1, subject.redis.timeout
      assert_equal 4, subject.redis.size
    end

  end

  class RedisUrlTests < UnitTests
    desc "RedisUrl"
    subject{ RedisUrl }

    should "build a redis url when passed an ip, port and db" do
      ip = Factory.string
      port = Factory.integer
      db = Factory.integer
      expected = "redis://#{ip}:#{port}/#{db}"
      assert_equal expected, subject.new(ip, port, db)
    end

    should "not return a url with an ip, port or db" do
      assert_nil subject.new(nil, Factory.integer, Factory.integer)
      assert_nil subject.new(Factory.string, nil, Factory.integer)
      assert_nil subject.new(Factory.string, Factory.integer, nil)
    end

  end

end
