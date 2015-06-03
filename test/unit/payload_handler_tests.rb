require 'assert'
require 'qs/payload_handler'

require 'qs/daemon_data'
require 'qs/queue_item'

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
      @message     = Factory.message
      @route_spy   = RouteSpy.new(@message.route_id)
      @daemon_data = Qs::DaemonData.new({
        :logger => Qs::NullLogger.new,
        :routes => [@route_spy]
      })
      encoded_payload = Qs::Payload.serialize(@message)
      @queue_item = Qs::QueueItem.new(Factory.string, encoded_payload)

      Assert.stub(Qs::Logger, :new){ |*args| QsLoggerSpy.new(*args) }

      @payload_handler = @handler_class.new(@daemon_data, @queue_item)
    end
    subject{ @payload_handler }

    should have_readers :daemon_data, :queue_item
    should have_readers :logger
    should have_imeths :run

    should "know its daemon data, queue item and logger" do
      assert_equal @daemon_data, subject.daemon_data
      assert_equal @queue_item,  subject.queue_item
      assert_equal @daemon_data.logger, subject.logger.passed_logger
      assert_equal @daemon_data.verbose_logging, subject.logger.verbose_logging
    end

  end

  class RunTests < InitTests
    desc "and run"
    setup do
      @payload_handler.run
    end

    should "run a route for the queue item" do
      assert_true @route_spy.run_called
      assert_equal @message, @route_spy.message_passed_to_run
      assert_equal @daemon_data, @route_spy.daemon_data_passed_to_run
    end

    should "build up its queue item as it processes it" do
      assert_equal @message, @queue_item.message
      assert_equal @route_spy.handler_class, @queue_item.handler_class
      assert_nil @queue_item.exception
      assert_instance_of Float, @queue_item.time_taken
    end

    should "log its processing of the queue item" do
      logger_spy = subject.logger
      exp = "[Qs] ===== Received message ====="
      assert_includes exp, logger_spy.verbose.info_logged
      exp = "[Qs]   Name:    #{@queue_item.message.route_id.inspect}"
      assert_includes exp, logger_spy.verbose.info_logged
      exp = "[Qs]   Params:  #{@queue_item.message.params.inspect}"
      assert_includes exp, logger_spy.verbose.info_logged
      exp = "[Qs]   Handler: #{@queue_item.handler_class}"
      assert_includes exp, logger_spy.verbose.info_logged
      exp = "[Qs] ===== Completed in #{@queue_item.time_taken}ms ====="
      assert_includes exp, logger_spy.verbose.info_logged
      assert_empty logger_spy.verbose.error_logged

      exp = SummaryLine.new({
        'time'    => @queue_item.time_taken,
        'handler' => @queue_item.handler_class,
        'name'    => @queue_item.message.route_id,
        'params'  => @queue_item.message.params
      })
      assert_equal 1, logger_spy.summary.info_logged.size
      assert_equal "[Qs] #{exp}", logger_spy.summary.info_logged.first
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
        :daemon_data     => @daemon_data,
        :queue_redis_key => @queue_item.queue_redis_key,
        :encoded_payload => @queue_item.encoded_payload,
        :message         => @queue_item.message,
        :handler_class   => @queue_item.handler_class
      }
      assert_equal exp, @error_handler_spy.context_hash
      assert_true @error_handler_spy.run_called
    end

    should "store the exception on the queue item" do
      assert_equal @error_handler_spy.exception, @queue_item.exception
    end

    should "log its processing of the queue item" do
      logger_spy = subject.logger
      exception = @queue_item.exception
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

    should "run an error handler if the queue item was started" do
      Assert.stub(@queue_item, :started){ true }
      assert_raises{ @payload_handler.run }

      passed_exception = @error_handler_spy.passed_exception
      assert_instance_of Qs::ShutdownError, passed_exception
      assert_equal @shutdown_error.message, passed_exception.message
      assert_equal @shutdown_error.backtrace, passed_exception.backtrace
      assert_true @error_handler_spy.run_called
    end

    should "not run an error handler if the queue item was started" do
      Assert.stub(@queue_item, :started){ false }
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
        'name'    => Factory.string,
        'params'  => Factory.string,
        'error'   => Factory.string
      }
      @summary_line = SummaryLine.new(@attrs)
    end
    subject{ @summary_line }

    should "build a string of all the attributes ordered with their values" do
      expected = "time=#{@attrs['time'].inspect} " \
                 "handler=#{@attrs['handler'].inspect} " \
                 "name=#{@attrs['name'].inspect} " \
                 "params=#{@attrs['params'].inspect} " \
                 "error=#{@attrs['error'].inspect}"
      assert_equal expected, subject
    end

  end

  class RouteSpy
    attr_reader :id
    attr_reader :message_passed_to_run, :daemon_data_passed_to_run
    attr_reader :run_called

    def initialize(message_route_id)
      @id = message_route_id
      @message_passed_to_run = nil
      @daemon_data_passed_to_run = nil
      @run_called = false
    end

    def handler_class
      TestHandler
    end

    def run(message, daemon_data)
      @message_passed_to_run = message
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
