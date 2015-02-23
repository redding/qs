require 'assert'
require 'qs/daemon'

require 'test/support/app_daemon'

module Qs::Daemon

  class SystemTests < Assert::Context
    desc "Qs::Daemon"
    setup do
      Qs.reset!
      @qs_test_mode = ENV['QS_TEST_MODE']
      ENV['QS_TEST_MODE'] = nil
      Qs.init

      @daemon = AppDaemon.new
      @daemon_runner = DaemonRunner.new(@daemon).tap(&:start)
    end
    teardown do
      @daemon_runner.stop
      Qs.redis.with{ |c| c.del('last_error') }
      Qs.reset!
      ENV['QS_TEST_MODE'] = @qs_test_mode
    end

  end

  class BasicJobTests < SystemTests
    desc "with a basic job added"
    setup do
      @key, @value = [Factory.string, Factory.string]
      AppQueue.add('basic', {
        'key'   => @key,
        'value' => @value
      })
    end

    should "run the job" do
      sleep 0.5
      assert_equal @value, Qs.redis.with{ |c| c.get(@key) }
    end

  end

  class JobThatErrorsTests < SystemTests
    desc "with a job that errors"
    setup do
      @error_message = Factory.text
      AppQueue.add('error', 'error_message' => @error_message)
    end

    should "run the configured error handler procs" do
      sleep 0.5
      exp = "RuntimeError: #{@error_message}"
      assert_equal exp, Qs.redis.with{ |c| c.get('last_error') }
    end

  end

  class TimeoutJobTests < SystemTests
    desc "with a job that times out"
    setup do
      AppQueue.add('timeout')
    end

    should "run the configured error handler procs" do
      sleep 1
      handler_class = AppHandlers::Timeout
      exp = "Qs::TimeoutError: #{handler_class} timed out " \
            "(#{handler_class.timeout}s)"
      assert_equal exp, Qs.redis.with{ |c| c.get('last_error') }
    end

  end

  class DaemonRunner
    def initialize(daemon)
      @daemon = daemon
      @thread = nil
    end

    def start
      @thread = @daemon.start
    end

    def stop
      @daemon.halt
      @thread.join if @thread
    end
  end

end
