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
      @orig_config = AppDaemon.configuration.to_hash
    end
    teardown do
      @daemon_runner.stop if @daemon_runner
      AppDaemon.configuration.apply(@orig_config) # reset daemon config
      Qs.redis.with{ |c| c.del('slow') }
      Qs.redis.with{ |c| c.del('last_error') }
      Qs.client.clear(AppQueue.redis_key)
      Qs.reset!
      ENV['QS_TEST_MODE'] = @qs_test_mode
    end

  end

  class RunningDaemonSetupTests < SystemTests
    setup do
      @daemon = AppDaemon.new
      @daemon_runner = DaemonRunner.new(@daemon)
      @thread = @daemon_runner.start
    end

  end

  class BasicJobTests < RunningDaemonSetupTests
    desc "with a basic job added"
    setup do
      @key, @value = [Factory.string, Factory.string]
      AppQueue.add('basic', {
        'key'   => @key,
        'value' => @value
      })
      @thread.join 0.5
    end

    should "run the job" do
      assert_equal @value, Qs.redis.with{ |c| c.get(@key) }
    end

  end

  class JobThatErrorsTests < RunningDaemonSetupTests
    desc "with a job that errors"
    setup do
      @error_message = Factory.text
      AppQueue.add('error', 'error_message' => @error_message)
      @thread.join 0.5
    end

    should "run the configured error handler procs" do
      exp = "RuntimeError: #{@error_message}"
      assert_equal exp, Qs.redis.with{ |c| c.get('last_error') }
    end

  end

  class TimeoutJobTests < RunningDaemonSetupTests
    desc "with a job that times out"
    setup do
      AppQueue.add('timeout')
      @thread.join 1 # let the daemon have time to process the job
    end

    should "run the configured error handler procs" do
      handler_class = AppHandlers::Timeout
      exp = "Qs::TimeoutError: #{handler_class} timed out " \
            "(#{handler_class.timeout}s)"
      assert_equal exp, Qs.redis.with{ |c| c.get('last_error') }
    end

  end

  class NoWorkersAvailableTests < SystemTests
    desc "when no workers are available"
    setup do
      AppDaemon.workers 0 # no workers available, don't do this
      @daemon = AppDaemon.new
      @daemon_runner = DaemonRunner.new(@daemon)
      @thread = @daemon_runner.start
    end

    should "shutdown when stopped" do
      @daemon.stop
      @thread.join 2 # give it time to shutdown, should be faster
      assert_false @thread.alive?
    end

    should "shutdown when halted" do
      @daemon.halt
      @thread.join 2 # give it time to shutdown, should be faster
      assert_false @thread.alive?
    end

  end

  class ShutdownWithoutTimeoutTests < SystemTests
    desc "without a shutdown timeout"
    setup do
      AppDaemon.shutdown_timeout nil # disable shutdown timeout
      @daemon = AppDaemon.new
      @daemon_runner = DaemonRunner.new(@daemon)
      @thread = @daemon_runner.start

      AppQueue.add('slow')
      @thread.join 1 # let the daemon have time to process the job
    end

    should "shutdown and let the job finished" do
      @daemon.stop
      @thread.join 10 # give it time to shutdown, should be faster
      assert_false @thread.alive?
      assert_equal 'finished', Qs.redis.with{ |c| c.get('slow') }
    end

    should "shutdown and not let the job finished" do
      @daemon.halt
      @thread.join 2 # give it time to shutdown, should be faster
      assert_false @thread.alive?
      assert_nil Qs.redis.with{ |c| c.get('slow') }
      exp = "Qs::ShutdownError"
      assert_equal exp, Qs.redis.with{ |c| c.get('last_error') }
    end

  end

  class ShutdownWithTimeoutTests < SystemTests
    desc "with a shutdown timeout"
    setup do
      AppDaemon.shutdown_timeout 1
      @daemon = AppDaemon.new
      @daemon_runner = DaemonRunner.new(@daemon)
      @thread = @daemon_runner.start

      AppQueue.add('slow')
      @thread.join 1 # let the daemon have time to process the job
    end

    should "shutdown and not let the job finished" do
      @daemon.stop
      @thread.join 2 # give it time to shutdown, should be faster
      assert_false @thread.alive?
      assert_nil Qs.redis.with{ |c| c.get('slow') }
      exp = "Qs::ShutdownError"
      assert_equal exp, Qs.redis.with{ |c| c.get('last_error') }
    end

    should "shutdown and not let the job finished" do
      @daemon.halt
      @thread.join 2 # give it time to shutdown, should be faster
      assert_false @thread.alive?
      assert_nil Qs.redis.with{ |c| c.get('slow') }
      exp = "Qs::ShutdownError"
      assert_equal exp, Qs.redis.with{ |c| c.get('last_error') }
    end

  end

  class ShutdownWithUnprocessedRedisItemTests < SystemTests
    desc "with a redis item that gets picked up but doesn't get processed"
    setup do
      Assert.stub(Qs::PayloadHandler, :new){ sleep 5 }

      AppDaemon.shutdown_timeout 1
      AppDaemon.workers 2
      @daemon = AppDaemon.new
      @daemon_runner = DaemonRunner.new(@daemon)
      @thread = @daemon_runner.start

      AppQueue.add('slow')
      AppQueue.add('slow')
      AppQueue.add('basic')
      @thread.join 1 # let the daemon have time to process jobs
    end

    should "shutdown and requeue the redis item" do
      @daemon.stop
      @thread.join 2 # give it time to shutdown, should be faster
      assert_false @thread.alive?
      # TODO - better way to read whats on a queue
      encoded_payloads = Qs.redis.with{ |c| c.lrange(AppQueue.redis_key, 0, 3) }
      names = encoded_payloads.map{ |sp| Qs::Payload.deserialize(sp).name }
      assert_equal ['basic', 'slow', 'slow'], names
    end

    should "shutdown and requeue the redis item" do
      @daemon.halt
      @thread.join 2 # give it time to shutdown, should be faster
      assert_false @thread.alive?
      # TODO - better way to read whats on a queue
      encoded_payloads = Qs.redis.with{ |c| c.lrange(AppQueue.redis_key, 0, 3) }
      names = encoded_payloads.map{ |sp| Qs::Payload.deserialize(sp).name }
      assert_equal ['basic', 'slow', 'slow'], names
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
