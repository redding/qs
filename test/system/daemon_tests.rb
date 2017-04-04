require 'assert'
require 'qs/daemon'

require 'test/support/app_queue'

module Qs::Daemon

  class SystemTests < Assert::Context
    desc "Qs::Daemon"
    setup do
      Qs.reset!
      @qs_test_mode = ENV['QS_TEST_MODE']
      ENV['QS_TEST_MODE'] = nil
      Qs.config.dispatcher_queue_name = 'qs-app-dispatcher'
      Qs.config.event_publisher       = 'Daemon System Tests'
      Qs.init
      AppQueue.sync_subscriptions

      @app_daemon_class = build_app_daemon_class
    end
    teardown do
      @daemon_runner.stop if @daemon_runner
      Qs.redis.connection do |c|
        keys = c.keys('*qs-app*')
        c.pipelined{ keys.each{ |k| c.del(k) } }
      end
      Qs.client.clear(AppQueue.redis_key)
      AppQueue.clear_subscriptions
      Qs.reset!
      ENV['QS_TEST_MODE'] = @qs_test_mode
    end

    private

    # manually build new anonymous app daemon classes for each run.  We do this
    # both to not mess with global state when tweaking config values for tests
    # and b/c there is no way to "reset" an existing class's config.
    def build_app_daemon_class
      Class.new do
        include Qs::Daemon

        name 'qs-app'

        logger Logger.new(ROOT_PATH.join('log/app_daemon.log').to_s)
        logger.datetime_format = "" # turn off the datetime in the logs

        verbose_logging true

        queue AppQueue

        error do |exception, context|
          return unless (message = context.message)
          payload_type = message.payload_type
          route_name   = message.route_name
          case(route_name)
          when 'error', 'timeout', 'qs-app:error', 'qs-app:timeout'
            error = "#{exception.class}: #{exception.message}"
            Qs.redis.connection{ |c| c.set("qs-app:last_#{payload_type}_error", error) }
          when 'slow', 'qs-app:slow'
            error = exception.class.to_s
            Qs.redis.connection{ |c| c.set("qs-app:last_#{payload_type}_error", error) }
          end
        end
      end
    end

    def setup_app_and_dispatcher_daemon
      @app_daemon        = @app_daemon_class.new
      @dispatcher_daemon = AppDispatcherDaemon.new
      @daemon_runner     = AppDaemonRunner.new(@app_daemon, @dispatcher_daemon)
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
      @app_thread.join(JOIN_SECONDS)
    end

    should "run the job" do
      assert_equal @value, Qs.redis.connection{ |c| c.get("qs-app:#{@key}") }
    end

  end

  class JobThatErrorsTests < RunningDaemonSetupTests
    desc "with a job that errors"
    setup do
      @error_message = Factory.text
      AppQueue.add('error', 'error_message' => @error_message)
      @app_thread.join(JOIN_SECONDS)
    end

    should "run the configured error handler procs" do
      exp = "RuntimeError: #{@error_message}"
      assert_equal exp, Qs.redis.connection{ |c| c.get('qs-app:last_job_error') }
    end

  end

  class TimeoutJobTests < RunningDaemonSetupTests
    desc "with a job that times out"
    setup do
      AppQueue.add('timeout')
      @app_thread.join(AppHandlers::Timeout::TIMEOUT_TIME + JOIN_SECONDS)
    end

    should "run the configured error handler procs" do
      handler_class = AppHandlers::Timeout
      exp = "Qs::TimeoutError: #{handler_class} timed out " \
            "(#{handler_class.timeout}s)"
      assert_equal exp, Qs.redis.connection{ |c| c.get('qs-app:last_job_error') }
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
      @app_thread.join(JOIN_SECONDS)
    end

    should "run the event" do
      assert_equal @value, Qs.redis.connection{ |c| c.get("qs-app:#{@key}") }
    end

  end

  class EventThatErrorsTests < RunningDaemonSetupTests
    desc "with an event that errors"
    setup do
      @error_message = Factory.text
      Qs.publish('qs-app', 'error', 'error_message' => @error_message)
      @app_thread.join(JOIN_SECONDS)
    end

    should "run the configured error handler procs" do
      exp = "RuntimeError: #{@error_message}"
      assert_equal exp, Qs.redis.connection{ |c| c.get('qs-app:last_event_error') }
    end

  end

  class TimeoutEventTests < RunningDaemonSetupTests
    desc "with an event that times out"
    setup do
      Qs.publish('qs-app', 'timeout')
      @app_thread.join(AppHandlers::Timeout::TIMEOUT_TIME + JOIN_SECONDS)
    end

    should "run the configured error handler procs" do
      handler_class = AppHandlers::TimeoutEvent
      exp = "Qs::TimeoutError: #{handler_class} timed out " \
            "(#{handler_class.timeout}s)"
      assert_equal exp, Qs.redis.connection{ |c| c.get('qs-app:last_event_error') }
    end

  end

  class ShutdownWithoutTimeoutTests < SystemTests
    desc "without a shutdown timeout"
    setup do
      @app_daemon_class.shutdown_timeout nil # disable shutdown timeout
      @nil_shutdown_timeout = 10 # something absurdly long, it should be faster
                                 # than this but want some timout to keep tests
                                 # from hanging in case it never shuts down

      setup_app_and_dispatcher_daemon

      AppQueue.add('slow')
      Qs.publish('qs-app', 'slow')
      @app_thread.join(JOIN_SECONDS)
    end

    should "shutdown and let the job and event finish" do
      @app_daemon.stop
      @app_thread.join(@nil_shutdown_timeout)

      assert_false @app_thread.alive?
      assert_equal 'finished', Qs.redis.connection{ |c| c.get('qs-app:slow') }
      assert_equal 'finished', Qs.redis.connection{ |c| c.get('qs-app:slow:event') }
    end

    should "shutdown and not let the job or event finish" do
      @app_daemon.halt
      @app_thread.join(@nil_shutdown_timeout)

      assert_false @app_thread.alive?
      assert_nil Qs.redis.connection{ |c| c.get('qs-app:slow') }

      exp = "Qs::ShutdownError"
      assert_equal exp, Qs.redis.connection{ |c| c.get('qs-app:last_job_error') }
      assert_nil Qs.redis.connection{ |c| c.get('qs-app:slow:event') }

      exp = "Qs::ShutdownError"
      assert_equal exp, Qs.redis.connection{ |c| c.get('qs-app:last_event_error') }
    end

  end

  class ShutdownWithTimeoutTests < SystemTests
    desc "with a shutdown timeout"
    setup do
      @shutdown_timeout = AppHandlers::Slow::SLOW_TIME * 0.5
      @app_daemon_class.shutdown_timeout @shutdown_timeout
      setup_app_and_dispatcher_daemon

      AppQueue.add('slow')
      Qs.publish('qs-app', 'slow')
      @app_thread.join(JOIN_SECONDS)
    end

    should "shutdown and not let the job or event finish" do
      @app_daemon.stop
      @app_thread.join(@shutdown_timeout + JOIN_SECONDS)

      assert_false @app_thread.alive?
      assert_nil Qs.redis.connection{ |c| c.get('qs-app:slow') }

      exp = "Qs::ShutdownError"
      assert_equal exp, Qs.redis.connection{ |c| c.get('qs-app:last_job_error') }
      assert_nil Qs.redis.connection{ |c| c.get('qs-app:slow:event') }

      exp = "Qs::ShutdownError"
      assert_equal exp, Qs.redis.connection{ |c| c.get('qs-app:last_event_error') }
    end

    should "shutdown and not let the job or event finish" do
      @app_daemon.halt
      @app_thread.join(@shutdown_timeout + JOIN_SECONDS)

      assert_false @app_thread.alive?
      assert_nil Qs.redis.connection{ |c| c.get('qs-app:slow') }

      exp = "Qs::ShutdownError"
      assert_equal exp, Qs.redis.connection{ |c| c.get('qs-app:last_job_error') }
      assert_nil Qs.redis.connection{ |c| c.get('qs-app:slow:event') }

      exp = "Qs::ShutdownError"
      assert_equal exp, Qs.redis.connection{ |c| c.get('qs-app:last_event_error') }
    end

  end

  class ShutdownWithUnprocessedQueueItemTests < SystemTests
    desc "with a queue item that gets picked up but doesn't get processed"
    setup do
      Assert.stub(Qs::PayloadHandler, :new) do
        sleep AppHandlers::Slow::SLOW_TIME + JOIN_SECONDS
      end

      @shutdown_timeout = AppHandlers::Slow::SLOW_TIME * 0.5
      @app_daemon_class.shutdown_timeout @shutdown_timeout
      @app_daemon_class.workers 2
      setup_app_and_dispatcher_daemon

      AppQueue.add('slow1')
      AppQueue.add('slow2')
      AppQueue.add('basic1')

      @app_thread.join(JOIN_SECONDS)
    end

    should "shutdown and requeue the queue item" do
      @app_daemon.stop
      @app_thread.join(@shutdown_timeout + JOIN_SECONDS)

      assert_false @app_thread.alive?

      encoded_payloads = Qs.redis.connection{ |c| c.lrange(AppQueue.redis_key, 0, 3) }
      names = encoded_payloads.map{ |sp| Qs::Payload.deserialize(sp).name }

      ['slow1', 'slow2', 'basic1'].each{ |n| assert_includes n, names }
    end

    should "shutdown and requeue the queue item" do
      @app_daemon.halt
      @app_thread.join(@shutdown_timeout + JOIN_SECONDS)

      assert_false @app_thread.alive?

      encoded_payloads = Qs.redis.connection{ |c| c.lrange(AppQueue.redis_key, 0, 4) }
      names = encoded_payloads.map{ |sp| Qs::Payload.deserialize(sp).name }

      ['slow1', 'slow2', 'basic1'].each{ |n| assert_includes n, names }
    end

  end

  class WithEnvProcessLabelTests < SystemTests
    desc "with a process label env var"
    setup do
      ENV['QS_PROCESS_LABEL'] = Factory.string

      @daemon = @app_daemon_class.new
    end
    teardown do
      ENV.delete('QS_PROCESS_LABEL')
    end
    subject{ @daemon }

    should "set the daemons process label to the env var" do
      assert_equal ENV['QS_PROCESS_LABEL'], subject.process_label
    end

  end

  class AppDispatcherDaemon
    include Qs::Daemon

    name 'qs-app-dispatcher'

    logger Logger.new(ROOT_PATH.join('log/app_dispatcher_daemon.log').to_s)
    logger.datetime_format = "" # turn off the datetime in the logs

    verbose_logging true

    # we build a "custom" dispatcher because we can't rely on Qs being initialized
    # when this is required
    queue Qs::DispatcherQueue.new({
      :queue_class            => Qs.config.dispatcher_queue_class,
      :queue_name             => 'qs-app-dispatcher',
      :job_name               => Qs.config.dispatcher_job_name,
      :job_handler_class_name => Qs.config.dispatcher_job_handler_class_name
    })
  end

  class AppDaemonRunner
    def initialize(app_daemon, dispatcher_daemon = nil)
      @app_daemon = app_daemon
      @dispatcher_daemon = dispatcher_daemon
      @app_thread = nil
      @dispatcher_thread = nil
    end

    def start
      @app_thread = @app_daemon.start
      @app_thread.join(JOIN_SECONDS)
      if @dispatcher_daemon
        @dispatcher_thread = @dispatcher_daemon.start
        @dispatcher_thread.join(JOIN_SECONDS)
      end
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
