require 'assert'
require 'qs/error_handler'

require 'qs/daemon_data'
require 'qs/queue'

class Qs::ErrorHandler

  class UnitTests < Assert::Context
    desc "Qs::ErrorHandler"
    setup do
      @exception       = Factory.exception
      @daemon_data     = Qs::DaemonData.new
      @queue_redis_key = Qs::Queue::RedisKey.new(Factory.string)
      @context_hash    = {
        :daemon_data     => @daemon_data,
        :queue_redis_key => @queue_redis_key,
        :encoded_payload => Factory.string,
        :message         => Factory.string,
        :handler_class   => Factory.string
      }

      @handler_class = Qs::ErrorHandler
    end
    subject{ @handler_class }

  end

  class InitSetupTests < UnitTests
    desc "when init"
    setup do
      # always make sure there are multiple error procs or tests can be false
      # positives
      @error_proc_spies = (1..(Factory.integer(3) + 1)).map{ ErrorProcSpy.new }
      Assert.stub(@daemon_data, :error_procs){ @error_proc_spies }
    end

  end

  class InitTests < InitSetupTests
    desc "when init"
    setup do
      @handler = @handler_class.new(@exception, @context_hash)
    end
    subject{ @handler }

    should have_readers :exception, :context
    should have_imeths :run

    should "know its exception and context" do
      assert_equal @exception, subject.exception
      exp = Qs::ErrorContext.new(@context_hash)
      assert_equal exp, subject.context
    end

    should "know its error procs" do
      assert_equal @error_proc_spies.reverse, subject.error_procs
    end

  end

  class RunTests < InitTests
    desc "and run"
    setup do
      @handler.run
    end

    should "call each of its procs" do
      subject.error_procs.each_with_index do |spy, index|
        assert_true spy.called
        assert_equal subject.exception, spy.exception
        assert_equal subject.context,   spy.context
      end
    end

  end

  class RunWithErrorProcExceptionsTests < InitSetupTests
    desc "and run with error procs that throw exceptions"
    setup do
      @proc_exceptions = @error_proc_spies.reverse.map do |spy|
        exception = Factory.exception(RuntimeError, @error_proc_spies.index(spy).to_s)
        spy.raise_exception = exception
        exception
      end

      @handler = @handler_class.new(@exception, @context_hash).tap(&:run)
    end
    subject{ @handler }

    should "pass the previously raised exception to the next proc" do
      exp = [@exception] + @proc_exceptions[0..-2]
      assert_equal exp, subject.error_procs.map(&:exception)
    end

    should "set its exception to the last exception thrown by the procs" do
      assert_equal @proc_exceptions.last, subject.exception
    end

  end

  class ErrorContextTests < UnitTests
    desc "ErrorContext"
    setup do
      @context = Qs::ErrorContext.new(@context_hash)
    end
    subject{ @context }

    should have_readers :daemon_data
    should have_readers :queue_name, :encoded_payload
    should have_readers :message, :handler_class

    should "know its attributes" do
      assert_equal @context_hash[:daemon_data], subject.daemon_data
      exp = Qs::Queue::RedisKey.parse_name(@context_hash[:queue_redis_key])
      assert_equal exp, subject.queue_name
      assert_equal @context_hash[:encoded_payload], subject.encoded_payload
      assert_equal @context_hash[:message], subject.message
      assert_equal @context_hash[:handler_class], subject.handler_class
    end

    should "know if it equals another context" do
      exp = Qs::ErrorContext.new(@context_hash)
      assert_equal exp, subject

      exp = Qs::ErrorContext.new({})
      assert_not_equal exp, subject
    end

  end

  class ErrorProcSpy
    attr_reader :called, :exception, :context
    attr_accessor :raise_exception

    def initialize
      @called = false
    end

    def call(exception, context)
      @called    = true
      @exception = exception
      @context   = context

      raise self.raise_exception if self.raise_exception
    end
  end

end
