require 'assert'
require 'qs/payload_handler'

require 'qs/daemon_data'
require 'qs/job'
require 'qs/redis_item'

class Qs::PayloadHandler

  class UnitTests < Assert::Context
    desc "Qs::PayloadHandler"
    setup do
      Qs.init
      @handler_class = Qs::PayloadHandler
    end
    subject{ @handler_class }

  end

  class InitTests < UnitTests
    desc "when init"
    setup do
      @job = Factory.job
      @route_spy = RouteSpy.new(@job.route_name)
      @daemon_data = Qs::DaemonData.new({
        :logger => Qs::NullLogger.new,
        :routes => [@route_spy]
      })
      serialized_payload = Qs.serialize(@job.to_payload)
      @redis_item = Qs::RedisItem.new(Factory.string, serialized_payload)

      Assert.stub(Qs::Logger, :new){ |*args| QsLoggerSpy.new(*args) }

      @payload_handler = @handler_class.new(@daemon_data, @redis_item)
    end
    subject{ @payload_handler }

    should have_readers :daemon_data, :redis_item
    should have_readers :logger
    should have_imeths :run

    should "know its daemon data, redis item and logger" do
      assert_equal @daemon_data, subject.daemon_data
      assert_equal @redis_item,  subject.redis_item
      assert_equal @daemon_data.logger, subject.logger.passed_logger
      assert_equal @daemon_data.verbose_logging, subject.logger.verbose_logging
    end

  end

  class RunTests < InitTests
    desc "and run"
    setup do
      @payload_handler.run
    end

    should "run a route for the redis item" do
      assert_true @route_spy.run_called
      assert_equal @job, @route_spy.job_passed_to_run
      assert_equal @daemon_data, @route_spy.daemon_data_passed_to_run
    end

    should "build up its redis item as it processes it" do
      assert_equal @job, @redis_item.job
      assert_equal @route_spy.handler_class, @redis_item.handler_class
      assert_nil @redis_item.exception
      assert_instance_of Float, @redis_item.time_taken
    end

    should "log its processing of the redis item" do
      logger_spy = subject.logger
      expected = "[Qs] ===== Running job ====="
      assert_includes expected, logger_spy.verbose.info_logged
      expected = "[Qs]   Job:     #{@redis_item.job.name.inspect}"
      assert_includes expected, logger_spy.verbose.info_logged
      expected = "[Qs]   Params:  #{@redis_item.job.params.inspect}"
      assert_includes expected, logger_spy.verbose.info_logged
      expected = "[Qs]   Handler: #{@redis_item.handler_class}"
      assert_includes expected, logger_spy.verbose.info_logged
      expected = "[Qs] ===== Completed in #{@redis_item.time_taken}ms ====="
      assert_includes expected, logger_spy.verbose.info_logged
      assert_empty logger_spy.verbose.error_logged

      expected = SummaryLine.new({
        'time'    => @redis_item.time_taken,
        'handler' => @redis_item.handler_class,
        'job'     => @redis_item.job.name,
        'params'  => @redis_item.job.params
      })
      assert_equal 1, logger_spy.summary.info_logged.size
      assert_equal "[Qs] #{expected}", logger_spy.summary.info_logged.first
      assert_empty logger_spy.summary.error_logged
    end

  end

  class RunWithExceptionSetupTests < InitTests
    setup do
      @route_exception = Factory.exception
      Assert.stub(@route_spy, :run){ raise @route_exception }
      Assert.stub(Qs::ErrorHandler, :new) do |*args|
        @error_handler_spy = ErrorHandlerSpy.new(*args)
      end
    end

  end

  class RunWithExceptionTests < RunWithExceptionSetupTests
    desc "and run with an exception"
    setup do
      @payload_handler.run
    end

    should "run an error handler" do
      assert_equal @route_exception, @error_handler_spy.passed_exception
      exp = {
        :daemon_data        => @daemon_data,
        :queue_redis_key    => @redis_item.queue_redis_key,
        :serialized_payload => @redis_item.serialized_payload,
        :job                => @redis_item.job,
        :handler_class      => @redis_item.handler_class
      }
      assert_equal exp, @error_handler_spy.context_hash
      assert_true @error_handler_spy.run_called
    end

    should "store the exception on the redis item" do
      assert_equal @error_handler_spy.exception, @redis_item.exception
    end

    should "log its processing of the redis item" do
      logger_spy = subject.logger
      exception = @redis_item.exception
      backtrace = exception.backtrace.join("\n")
      exp = "[Qs] #{exception.class}: #{exception.message}\n#{backtrace}"
      assert_equal exp, logger_spy.verbose.error_logged.first
    end

  end

  class RunWithShutdownErrorTests < RunWithExceptionSetupTests
    desc "and run with a dat worker pool shutdown error"
    setup do
      @shutdown_error = DatWorkerPool::ShutdownError.new(Factory.text)
      Assert.stub(@route_spy, :run){ raise @shutdown_error }
    end

    should "run an error handler if the redis item was started" do
      Assert.stub(@redis_item, :started){ true }
      assert_raises{ @payload_handler.run }

      passed_exception = @error_handler_spy.passed_exception
      assert_instance_of Qs::ShutdownError, passed_exception
      assert_equal @shutdown_error.message, passed_exception.message
      assert_equal @shutdown_error.backtrace, passed_exception.backtrace
      assert_true @error_handler_spy.run_called
    end

    should "not run an error handler if the redis item was started" do
      Assert.stub(@redis_item, :started){ false }
      assert_raises{ @payload_handler.run }

      assert_nil @error_handler_spy
    end

    should "raise the shutdown error" do
      assert_raises(@shutdown_error.class){ @payload_handler.run }
    end

  end

  class RunWithExceptionWhileDebuggingTests < RunWithExceptionSetupTests
    desc "and run with an exception"
    setup do
      ENV['QS_DEBUG'] = '1'
    end
    teardown do
      ENV.delete('QS_DEBUG')
    end

    should "raise the exception" do
      assert_raises(@route_exception.class){ @payload_handler.run }
    end

  end

  class SummaryLineTests < UnitTests
    desc "SummaryLine"
    setup do
      @attrs = {
        'time'    => Factory.string,
        'handler' => Factory.string,
        'job'     => Factory.string,
        'params'  => Factory.string,
        'error'   => Factory.string
      }
      @summary_line = SummaryLine.new(@attrs)
    end
    subject{ @summary_line }

    should "build a string of all the attributes ordered with their values" do
      expected = "time=#{@attrs['time'].inspect} " \
                 "handler=#{@attrs['handler'].inspect} " \
                 "job=#{@attrs['job'].inspect} " \
                 "params=#{@attrs['params'].inspect} " \
                 "error=#{@attrs['error'].inspect}"
      assert_equal expected, subject
    end

  end

  class RouteSpy
    attr_reader :name
    attr_reader :job_passed_to_run, :daemon_data_passed_to_run
    attr_reader :run_called

    def initialize(job_route_name)
      @name = job_route_name
      @job_passed_to_run = nil
      @daemon_data_passed_to_run = nil
      @run_called = false
    end

    def handler_class
      TestHandler
    end

    def run(job, daemon_data)
      @job_passed_to_run = job
      @daemon_data_passed_to_run = daemon_data
      @run_called = true
    end

    TestHandler = Class.new
  end

  class ErrorHandlerSpy
    attr_reader :passed_exception, :context_hash, :exception, :run_called

    def initialize(exception, context_hash)
      @passed_exception = exception
      @context_hash     = context_hash
      @exception        = Factory.exception
      @run_called       = false
    end

    def run
      @run_called = true
    end
  end

  class QsLoggerSpy
    attr_reader :passed_logger, :verbose_logging
    attr_reader :summary, :verbose

    def initialize(passed_logger, verbose_logging)
      @passed_logger = passed_logger
      @verbose_logging = verbose_logging
      @summary = LoggerSpy.new
      @verbose = LoggerSpy.new
    end

    class LoggerSpy
      attr_reader :info_logged, :error_logged

      def initialize
        @info_logged = []
        @error_logged = []
      end

      def info(message);  @info_logged << message;  end
      def error(message); @error_logged << message; end
    end
  end

end
