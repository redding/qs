require 'assert'
require 'qs/payload_handler'

require 'qs/daemon_data'
require 'qs/job'

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
      @route_spy = RouteSpy.new
      @daemon_data = Qs::DaemonData.new({
        :logger => Qs::NullLogger.new,
        :routes => [@route_spy]
      })
      @job = Qs::Job.new(@route_spy.name, Factory.string => Factory.string)
      @serialized_payload = Qs.serialize(@job.to_payload)

      Assert.stub(Qs::Logger, :new){ |*args| QsLoggerSpy.new(*args) }

      @payload_handler = @handler_class.new(@daemon_data, @serialized_payload)
    end
    subject{ @payload_handler }

    should have_readers :daemon_data, :serialized_payload, :logger
    should have_imeths :run

    should "know its daemon data, payload and logger" do
      assert_equal @daemon_data, subject.daemon_data
      assert_equal @serialized_payload, subject.serialized_payload
      assert_equal @daemon_data.logger, subject.logger.passed_logger
      assert_equal @daemon_data.verbose_logging, subject.logger.verbose_logging
    end

  end

  class RunTests < InitTests
    desc "and run"
    setup do
      @processed_payload = @payload_handler.run
    end

    should "return a processed payload" do
      assert_instance_of ProcessedPayload, @processed_payload
      assert_equal @job, @processed_payload.job
      assert_equal @route_spy.handler_class, @processed_payload.handler_class
      assert_nil @processed_payload.exception
      assert_instance_of Float, @processed_payload.time_taken
    end

    should "run a route for the passed payload" do
      assert_true @route_spy.run_called
      assert_equal @job, @route_spy.job_passed_to_run
      assert_equal @daemon_data, @route_spy.daemon_data_passed_to_run
    end

    should "log its processing of the payload" do
      logger_spy = subject.logger
      expected = "[Qs] ===== Running job ====="
      assert_includes expected, logger_spy.verbose.info_logged
      expected = "[Qs]   Job:     #{@processed_payload.job.name.inspect}"
      assert_includes expected, logger_spy.verbose.info_logged
      expected = "[Qs]   Params:  #{@processed_payload.job.params.inspect}"
      assert_includes expected, logger_spy.verbose.info_logged
      expected = "[Qs]   Handler: #{@processed_payload.handler_class}"
      assert_includes expected, logger_spy.verbose.info_logged
      expected = "[Qs] ===== Completed in #{@processed_payload.time_taken}ms ====="
      assert_includes expected, logger_spy.verbose.info_logged
      assert_empty logger_spy.verbose.error_logged

      expected = SummaryLine.new({
        'time'    => @processed_payload.time_taken,
        'handler' => @processed_payload.handler_class,
        'job'     => @processed_payload.job.name,
        'params'  => @processed_payload.job.params
      })
      assert_equal 1, logger_spy.summary.info_logged.size
      assert_equal "[Qs] #{expected}", logger_spy.summary.info_logged.first
      assert_empty logger_spy.summary.error_logged
    end

  end

  class RunWithExceptionTests < InitTests
    desc "and run with an exception"
    setup do
      @route_exception = Factory.exception
      Assert.stub(@route_spy, :run){ raise @route_exception }
      @error_handler_spy = ErrorHandlerSpy.new
      Assert.stub(Qs::ErrorHandler, :new) do |e, d, j|
        @error_handler_spy.passed_exception = e
        @error_handler_spy.passed_daemon_data = d
        @error_handler_spy.passed_job = j
        @error_handler_spy
      end

      @processed_payload = @payload_handler.run
    end

    should "run an error handler" do
      assert_equal @route_exception, @error_handler_spy.passed_exception
      assert_equal @daemon_data, @error_handler_spy.passed_daemon_data
      assert_equal @job, @error_handler_spy.passed_job
      assert_true @error_handler_spy.run_called
    end

    should "return a processed payload with an exception" do
      assert_equal @error_handler_spy.exception, @processed_payload.exception
    end

    should "log its processing of the payload" do
      logger_spy = subject.logger
      exception = @processed_payload.exception
      backtrace = exception.backtrace.join("\n")
      expected = "[Qs] #{exception.class}: #{exception.message}\n#{backtrace}"
      assert_equal expected, logger_spy.verbose.error_logged.first
    end

  end

  class RunWithExceptionWhileDebuggingTests < InitTests
    desc "and run with an exception"
    setup do
      ENV['QS_DEBUG'] = '1'
      @route_exception = Factory.exception
      Assert.stub(@route_spy, :run){ raise @route_exception }
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

    def initialize
      @name = Factory.string
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
    attr_accessor :passed_exception, :passed_daemon_data, :passed_job
    attr_reader :exception, :run_called

    def initialize
      @exception = Factory.exception
      @run_called = false
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
