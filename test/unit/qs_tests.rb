require 'assert'
require 'qs'
require 'qs/redis_connection'

module Qs

  class BaseTests < Assert::Context
    desc "the Qs module"
    subject { Qs }

    should have_imeths :config, :configure, :init, :after_fork
    should have_imeths :queues, :register, :redis

    should "know its config singleton" do
      assert_same Config, subject.config
    end

    should "add a queue to it's set with #register" do
      test_queue = Class.new
      subject.register(test_queue)

      assert_includes test_queue, subject.queues

      subject.queues.delete(test_queue)
    end

    should "complain if accessing the redis connection without a block" do
      assert_raises(ArgumentError){ subject.redis }
      assert_nothing_raised do
        subject.redis{|conn| }
      end
    end

    # Note: don't really need to explicitly test the configure/init meths
    # nothing runs as expected if they aren't working

  end

  class ConfigTests < Assert::Context
    desc "the Qs Config singleton"
    subject { Config }

    should have_imeths :queue_key_prefix, :timeout, :logger
    should have_imeths :default_timeout, :null_logger

    should "know its default_timeout" do
      assert_equal 300, subject.default_timeout
    end

    should "know its null logger" do
      assert_kind_of ::Logger, subject.null_logger
    end

    should "set a default queue_key_prefix" do
      assert_equal 'qs', subject.queue_key_prefix
    end

    should "use its default timeout for its timeout setting (by default)" do
      assert_equal subject.default_timeout, subject.timeout
    end

    should "use its null logger for its logger setting (by default)" do
      assert_same subject.null_logger, subject.logger
    end

  end

  class RedisConfigTests < ConfigTests
    desc "redis configs"
    subject { Config.redis }

    should have_imeths :url, :ns, :size, :timeout, :driver

    should "know its redis config values" do
      assert_equal 'redis://localhost:6379/0', subject.url
      assert_equal 'qs-test', subject.redis_ns
      assert_equal 1, subject.size
      assert_equal 1, subject.timeout
      assert_equal 'ruby', subject.driver
    end

  end

end
