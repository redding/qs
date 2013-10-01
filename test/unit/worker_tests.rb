require 'assert'
require 'qs/worker'

require 'qs/queue'

class Qs::Worker

  class UnitTests < Assert::Context
    desc "Qs::Worker"
    setup do
      @spy_logger   = SpyLogger.new
      @queue        = Qs::Queue.new
      @queue.logger = @spy_logger
      @error_procs  = [ proc{ } ]
      @worker = Qs::Worker.new(@queue, @error_procs)
    end
    subject{ @worker }

    should have_imeths :run

  end

  class RunTests < UnitTests
    setup do
      @encoded_job   = 'some job'
      @job           = Qs::Job.new({})
      @handler_class = Class.new
      @spy_runner    = SpyRunner.new

      Qs::Job.stubs(:parse).tap do |s|
        s.with(@encoded_job)
        s.returns(@job)
      end
      @queue.stubs(:handler_class_for).tap do |s|
        s.with(@job.type, @job.name)
        s.returns(@handler_class)
      end
      Qs::Runner.stubs(:new).tap do |s|
        s.with(@handler_class, @job, @queue.logger)
        s.returns(@spy_runner)
      end
    end
    teardown do
      Qs::Runner.unstub(:new)
      Qs::Job.unstub(:parse)
    end
  end

  class RunThatSucceedsTests < RunTests
    desc "run that succeeds"
    setup do
      @worker.run(@encoded_job)
    end

    should "parse the job, find a handler class and run it" do
      assert @spy_runner.run_called
    end

    should "log the process of running the job" do
      expected = [
        "[Qs] ===== Received job =====",
        "[Qs]   Type:    #{@job.type.inspect}",
        "[Qs]   Name:    #{@job.name.inspect}",
        "[Qs]   Params:  #{@job.params.inspect}",
        "[Qs]   Handler: #{@handler_class.inspect}",
        "[Qs] ===== Completed in 0.0s ====="
      ]
      assert_equal expected, @spy_logger.info_messages
    end

  end

  class RunThatFailsTests < RunTests
    desc "run that fails"
    setup do
      @exception = RuntimeError.new('test')
      @spy_error_handler = SpyErrorHandler.new

      @spy_runner.stubs(:run).raises(@exception)
      Qs::ErrorHandler.stubs(:new).tap do |s|
        s.with(@queue, @error_procs)
        s.returns(@spy_error_handler)
      end

      @worker = Qs::Worker.new(@queue, @error_procs)
      @worker.run(@encoded_job)
    end

    should "have run the error handler with the exception and job" do
      error_handled = @spy_error_handler.errors_handled.last
      assert_equal @exception, error_handled.exception
      assert_equal @job,       error_handled.job
    end

    should "log the exception" do
      expected = [
        "[Qs] #{@exception.class}: #{@exception.message}",
        "[Qs] #{@exception.backtrace.join("\n")}"
      ]
      assert_equal expected, @spy_logger.error_messages
    end

  end

  class SpyLogger
    attr_reader :info_messages, :error_messages
    def initialize
      @info_messages  = []
      @error_messages = []
    end
    def info(message)
      @info_messages  << message
    end
    def error(message)
      @error_messages << message
    end
  end

  class SpyRunner
    attr_reader :run_called
    def initialize
      @run_called = false
    end
    def run
      @run_called = true
    end
  end

  class SpyErrorHandler
    attr_reader :errors_handled
    def initialize
      @errors_handled = []
    end
    def run(exception, job)
      @errors_handled << ErrorHandled.new(exception, job)
      exception
    end
  end

  ErrorHandled = Struct.new(:exception, :job)

end
