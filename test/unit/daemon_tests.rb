require 'assert'
require 'qs/daemon'

module Qs::Daemon

  class UnitTests < Assert::Context
    desc "Qs::Daemon"
    setup do
      @daemon_class = Class.new{ include Qs::Daemon }
      @queue = @daemon_class.configuration.queue
      @daemon = @daemon_class.new
    end
    subject{ @daemon }

    should have_cmeths :configuration
    should have_cmeths :queue
    should have_cmeths :pid_file
    should have_cmeths :min_workers, :max_workers, :workers
    should have_cmeths :wait_timeout, :shutdown_timeout

    should have_readers :queue_name, :pid_file, :logger

    should "return it's configuration's pid file with #pid_file" do
      assert_equal @daemon_class.configuration.pid_file, subject.pid_file
    end

    should "return it's configuration's queue's name with #queue_name" do
      assert_equal @queue.name, subject.queue_name
    end

    should "return it's queue's logger with #logger" do
      assert_equal @queue.logger, subject.logger
    end

  end

  class ValidateConfigurationTests < UnitTests
    desc "with an invalid config"
    setup do
      @daemon_class.configuration.stubs(:validate!).raises(StandardError)
    end
    teardown do
      @daemon_class.configuration.unstub(:validate!)
    end

    should "validate the configuration when initialized" do
      assert_raises(StandardError){ @daemon_class.new }
    end

  end

  class ClassMethodTests < UnitTests
    desc "class"
    subject{ @daemon_class }

    should "return an instance of a Configuration with #configuration" do
      assert_instance_of Configuration, subject.configuration
    end

    should "allow reading/writing the configuration's queue" do
      test_queue = Qs::Queue.new
      assert_nothing_raised{ subject.queue test_queue }
      assert_equal test_queue, subject.queue
    end

    should "allow reading/writing the configuration's pid file" do
      assert_nothing_raised{ subject.pid_file 'test.pid' }
      assert_equal 'test.pid', subject.pid_file
    end

    should "allow reading/writing the configuration's min workers" do
      assert_nothing_raised{ subject.min_workers 2 }
      assert_equal 2, subject.min_workers
    end

    should "allow reading/writing the configuration's max workers" do
      assert_nothing_raised{ subject.max_workers 2 }
      assert_equal 2, subject.max_workers
    end

    should "allow setting both it's min and max workers with #workers" do
      assert_nothing_raised{ subject.workers 3 }
      assert_equal 3, subject.min_workers
      assert_equal 3, subject.max_workers
    end

    should "allow reading/writing the configuration's wait timeout" do
      assert_nothing_raised{ subject.wait_timeout 1 }
      assert_equal 1, subject.wait_timeout
    end

    should "allow reading/writing the configuration's shutdown timeout" do
      assert_nothing_raised{ subject.shutdown_timeout 15 }
      assert_equal 15, subject.shutdown_timeout
    end

  end

end
