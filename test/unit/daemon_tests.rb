require 'assert'
require 'qs/daemon'

module Qs::Daemon

  class UnitTests < Assert::Context
    desc "Qs::Daemon"
    setup do
      @daemon_class = Class.new{ include Qs::Daemon }
      @daemon = @daemon_class.new
    end
    subject{ @daemon }

    should have_cmeths :configuration
    should have_cmeths :pid_file
    should have_cmeths :min_workers, :max_workers, :workers
    should have_cmeths :wait_timeout, :shutdown_timeout

    should have_imeths :pid_file

    should "build it's configuration from it's class's configuration" do
      @daemon_class.configuration.pid_file = 'test.pid'
      daemon = @daemon_class.new
      assert_equal 'test.pid', daemon.configuration.pid_file
    end

    should "return it's configuration's pid file with #pid_file" do
      assert_equal subject.configuration.pid_file, subject.pid_file
    end

  end

  class ValidateConfigurationTests < UnitTests
    desc "with an invalid config"
    setup do
      config = mock('Qs::Daemon::Configuration')
      Configuration.stubs(:new).returns(config)
      config.stubs(:validate!).raises(StandardError)
    end
    teardown do
      Configuration.unstub(:new)
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
