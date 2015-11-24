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
      Qs.config.dispatcher.queue_name = 'qs-app-dispatcher'
      Qs.config.event_publisher       = 'Daemon System Tests'
      Qs.init
      AppQueue.sync_subscriptions
      @orig_config = AppDaemon.configuration.to_hash
    end
    teardown do
      @daemon_runner.stop if @daemon_runner
      AppDaemon.configuration.apply(@orig_config) # reset daemon config
      Qs.redis.with do |c|
        keys = c.keys('*qs-app*')
        c.pipelined{ keys.each{ |k| c.del(k) } }
      end
      Qs.client.clear(AppQueue.redis_key)
      AppQueue.clear_subscriptions
      Qs.reset!
      ENV['QS_TEST_MODE'] = @qs_test_mode
    end

    private

    def setup_app_and_dispatcher_daemon
      @app_daemon        = AppDaemon.new
      @dispatcher_daemon = DispatcherDaemon.new
      @daemon_runner     = DaemonRunner.new(@app_daemon, @dispatcher_daemon)
      @app_thread        = @daemon_runner.start
    end

  end

  class RunningDaemonSetupTests < SystemTests
    setup do
      setup_app_and_dispatcher_daemon
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
      @app_thread.join 0.5
    end

    should "run the job" do
      assert_equal @value, Qs.redis.with{ |c| c.get("qs-app:#{@key}") }
    end

  end

  class JobThatErrorsTests < RunningDaemonSetupTests
    desc "with a job that errors"
    setup do
      @error_message = Factory.text
      AppQueue.add('error', 'error_message' => @error_message)
      @app_thread.join 0.5
    end

    should "run the configured error handler procs" do
      exp = "RuntimeError: #{@error_message}"
      assert_equal exp, Qs.redis.with{ |c| c.get('qs-app:last_job_error') }
    end

  end

  class TimeoutJobTests < RunningDaemonSetupTests
    desc "with a job that times out"
    setup do
      AppQueue.add('timeout')
      @app_thread.join 1 # let the daemon have time to process the job
    end

    should "run the configured error handler procs" do
      handler_class = AppHandlers::Timeout
      exp = "Qs::TimeoutError: #{handler_class} timed out " \
            "(#{handler_class.timeout}s)"
      assert_equal exp, Qs.redis.with{ |c| c.get('qs-app:last_job_error') }
    end

  end

  class BasicEventTests < RunningDaemonSetupTests
    desc "with a basic event added"
    setup do
      @key, @value = [Factory.string, Factory.string]
      Qs.publish('qs-app', 'basic', {
        'key'   => @key,
        'value' => @value
      })
      @app_thread.join 0.5
    end

    should "run the event" do
      assert_equal @value, Qs.redis.with{ |c| c.get("qs-app:#{@key}") }
    end

  end

  class EventThatErrorsTests < RunningDaemonSetupTests
    desc "with an event that errors"
    setup do
      @error_message = Factory.text
      Qs.publish('qs-app', 'error', 'error_message' => @error_message)
      @app_thread.join 0.5
    end

    should "run the configured error handler procs" do
      exp = "RuntimeError: #{@error_message}"
      assert_equal exp, Qs.redis.with{ |c| c.get('qs-app:last_event_error') }
    end

  end

  class TimeoutEventTests < RunningDaemonSetupTests
    desc "with an event that times out"
    setup do
      Qs.publish('qs-app', 'timeout')
      @app_thread.join 1 # let the daemon have time to process the job
    end

    should "run the configured error handler procs" do
      handler_class = AppHandlers::TimeoutEvent
      exp = "Qs::TimeoutError: #{handler_class} timed out " \
            "(#{handler_class.timeout}s)"
      assert_equal exp, Qs.redis.with{ |c| c.get('qs-app:last_event_error') }
    end

  end

  class ShutdownWithoutTimeoutTests < SystemTests
    desc "without a shutdown timeout"
    setup do
      AppDaemon.shutdown_timeout nil # disable shutdown timeout
      setup_app_and_dispatcher_daemon

      AppQueue.add('slow')
      Qs.publish('qs-app', 'slow')
      @app_thread.join 1 # let the daemon have time to process the job and event
    end

    should "shutdown and let the job and event finish" do
      @app_daemon.stop
      @app_thread.join 10 # give it time to shutdown, should be faster
      assert_false @app_thread.alive?
      assert_equal 'finished', Qs.redis.with{ |c| c.get('qs-app:slow') }
      assert_equal 'finished', Qs.redis.with{ |c| c.get('qs-app:slow:event') }
    end

    should "shutdown and not let the job or event finish" do
      @app_daemon.halt
      @app_thread.join 2 # give it time to shutdown, should be faster
      assert_false @app_thread.alive?
      assert_nil Qs.redis.with{ |c| c.get('qs-app:slow') }
      exp = "Qs::ShutdownError"
      assert_equal exp, Qs.redis.with{ |c| c.get('qs-app:last_job_error') }
      assert_nil Qs.redis.with{ |c| c.get('qs-app:slow:event') }
      exp = "Qs::ShutdownError"
      assert_equal exp, Qs.redis.with{ |c| c.get('qs-app:last_event_error') }
    end

  end

  class ShutdownWithTimeoutTests < SystemTests
    desc "with a shutdown timeout"
    setup do
      AppDaemon.shutdown_timeout 1
      setup_app_and_dispatcher_daemon

      AppQueue.add('slow')
      Qs.publish('qs-app', 'slow')
      @app_thread.join 1 # let the daemon have time to process the job and event
    end

    should "shutdown and not let the job or event finish" do
      @app_daemon.stop
      @app_thread.join 2 # give it time to shutdown, should be faster
      assert_false @app_thread.alive?
      assert_nil Qs.redis.with{ |c| c.get('qs-app:slow') }
      exp = "Qs::ShutdownError"
      assert_equal exp, Qs.redis.with{ |c| c.get('qs-app:last_job_error') }
      assert_nil Qs.redis.with{ |c| c.get('qs-app:slow:event') }
      exp = "Qs::ShutdownError"
      assert_equal exp, Qs.redis.with{ |c| c.get('qs-app:last_event_error') }
    end

    should "shutdown and not let the job or event finish" do
      @app_daemon.halt
      @app_thread.join 2 # give it time to shutdown, should be faster
      assert_false @app_thread.alive?
      assert_nil Qs.redis.with{ |c| c.get('qs-app:slow') }
      exp = "Qs::ShutdownError"
      assert_equal exp, Qs.redis.with{ |c| c.get('qs-app:last_job_error') }
      assert_nil Qs.redis.with{ |c| c.get('qs-app:slow:event') }
      exp = "Qs::ShutdownError"
      assert_equal exp, Qs.redis.with{ |c| c.get('qs-app:last_event_error') }
    end

  end

  class ShutdownWithUnprocessedQueueItemTests < SystemTests
    desc "with a queue item that gets picked up but doesn't get processed"
    setup do
      Assert.stub(Qs::PayloadHandler, :new){ sleep 5 }

      AppDaemon.shutdown_timeout 1
      AppDaemon.workers 2
      setup_app_and_dispatcher_daemon

      AppQueue.add('slow')
      AppQueue.add('slow')
      AppQueue.add('basic')
      @app_thread.join 1 # let the daemon have time to process jobs
    end

    should "shutdown and requeue the queue item" do
      @app_daemon.stop
      @app_thread.join 2 # give it time to shutdown, should be faster
      assert_false @app_thread.alive?
      encoded_payloads = Qs.redis.with{ |c| c.lrange(AppQueue.redis_key, 0, 3) }
      names = encoded_payloads.map{ |sp| Qs::Payload.deserialize(sp).name }
      assert_equal ['basic', 'slow', 'slow'], names
    end

    should "shutdown and requeue the queue item" do
      @app_daemon.halt
      @app_thread.join 2 # give it time to shutdown, should be faster
      assert_false @app_thread.alive?
      encoded_payloads = Qs.redis.with{ |c| c.lrange(AppQueue.redis_key, 0, 3) }
      names = encoded_payloads.map{ |sp| Qs::Payload.deserialize(sp).name }
      assert_equal ['basic', 'slow', 'slow'], names
    end

  end

  class WithEnvProcessLabelTests < SystemTests
    desc "with a process label env var"
    setup do
      ENV['QS_PROCESS_LABEL'] = Factory.string

      @daemon = AppDaemon.new
    end
    teardown do
      ENV.delete('QS_PROCESS_LABEL')
    end
    subject{ @daemon }

    should "set the daemons process label to the env var" do
      assert_equal ENV['QS_PROCESS_LABEL'], subject.process_label
    end

  end

  class DaemonRunner
    def initialize(app_daemon, dispatcher_daemon = nil)
      @app_daemon = app_daemon
      @dispatcher_daemon = dispatcher_daemon
      @app_thread = nil
      @dispatcher_thread = nil
    end

    def start
      @app_thread = @app_daemon.start
      @dispatcher_thread = @dispatcher_daemon.start if @dispatcher_daemon
      @app_thread
    end

    def stop
      @app_daemon.halt
      @dispatcher_daemon.halt if @dispatcher_daemon
      @app_thread.join if @app_thread
      @dispatcher_thread.join if @dispatcher_thread
    end
  end

end
