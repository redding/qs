require 'assert'
require 'qs/daemon'

require 'ns-options/assert_macros'
require 'qs/queue'

module Qs::Daemon

  class UnitTests < Assert::Context
    desc "Qs::Daemon"
    setup do
      @daemon_class = Class.new{ include Qs::Daemon }
    end
    subject{ @daemon_class }

  end

  class ConfigurationTests < UnitTests
    include NsOptions::AssertMacros

    desc "Configuration"
    setup do
      @queue = Qs::Queue.new do
        name Factory.string
        job_handler_ns 'Qs::Daemon'
        job 'test', 'TestHandler'
      end

      @configuration = Configuration.new.tap do |c|
        c.name Factory.string
        c.queues << @queue
      end
    end
    subject{ @configuration }

    should have_options :name, :pid_file
    should have_options :min_workers, :max_workers
    should have_options :verbose_logging, :logger
    should have_options :shutdown_timeout
    should have_accessors :init_procs, :error_procs
    should have_accessors :queues
    should have_imeths :routes
    should have_imeths :to_hash
    should have_imeths :valid?, :validate!

    should "be an ns-options proxy" do
      assert_includes NsOptions::Proxy, subject.class
    end

    should "default its options" do
      config = Configuration.new
      assert_nil config.name
      assert_nil config.pid_file
      assert_equal 1, config.min_workers
      assert_equal 4, config.max_workers
      assert_true config.verbose_logging
      assert_instance_of Qs::NullLogger, config.logger
      assert_equal [], config.init_procs
      assert_equal [], config.error_procs
      assert_equal [], config.queues
      assert_equal [], config.routes
    end

    should "not be valid by default" do
      assert_false subject.valid?
    end

    should "know its routes" do
      assert_equal subject.queues.map(&:routes).flatten, subject.routes
    end

    should "include its error procs, queue redis keys and routes in its hash" do
      config_hash = subject.to_hash
      assert_equal subject.error_procs, config_hash[:error_procs]
      expected = subject.queues.map(&:redis_key)
      assert_equal expected, config_hash[:queue_redis_keys]
      assert_equal subject.routes, config_hash[:routes]
    end

    should "call its init procs when validated" do
      called = false
      subject.init_procs << proc{ called = true }
      subject.validate!
      assert_true called
    end

    should "ensure its required options have been set when validated" do
      subject.name = nil
      assert_raises(InvalidError){ subject.validate! }
      subject.name = Factory.string

      subject.queues = []
      assert_raises(InvalidError){ subject.validate! }
      subject.queues << @queue

      assert_nothing_raised{ subject.validate! }
    end

    should "validate its routes when validated" do
      subject.routes.each{ |route| assert_nil route.handler_class }
      subject.validate!
      subject.routes.each{ |route| assert_not_nil route.handler_class }
    end

    should "be valid after being validated" do
      assert_false subject.valid?
      subject.validate!
      assert_true subject.valid?
    end

    should "only be able to be validated once" do
      called = 0
      subject.init_procs << proc{ called += 1 }
      subject.validate!
      assert_equal 1, called
      subject.validate!
      assert_equal 1, called
    end

  end

  TestHandler = Class.new

end
