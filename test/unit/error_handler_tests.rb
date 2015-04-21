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
      @queue_name      = Factory.string
      @queue_redis_key = Qs::Queue::RedisKey.new(@queue_name)
      @context_hash    = {
        :daemon_data        => @daemon_data,
        :queue_redis_key    => @queue_redis_key,
        :serialized_payload => Factory.string,
        :job                => Factory.string,
        :handler_class      => Factory.string
      }

      @handler_class = Qs::ErrorHandler
    end
    subject{ @handler_class }

  end

  class InitTests < UnitTests
    desc "when init"
    setup do
      @call_count = 0
      @first_called_at = nil
      @second_called_at = nil
      @args_passed_to_error_proc = nil
      first_error_proc = proc do |*args|
        @args_passed_to_error_proc = args
        @first_called_at = (@call_count += 1)
      end
      second_error_proc = proc{ @second_called_at = (@call_count += 1) }
      Assert.stub(@daemon_data, :error_procs){ [first_error_proc, second_error_proc] }

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
      assert_equal @daemon_data.error_procs.reverse, subject.error_procs
    end

  end

  class RunTests < InitTests
    desc "and run"
    setup do
      @handler.run
    end

    should "pass its exception and context to the error procs" do
      assert_not_nil @args_passed_to_error_proc
      assert_includes subject.exception, @args_passed_to_error_proc
      assert_includes subject.context,   @args_passed_to_error_proc
    end

    should "call each of its error procs" do
      assert_equal 1, @second_called_at
      assert_equal 2, @first_called_at
    end

  end

  class RunAndErrorProcThrowsExceptionTests < UnitTests
    desc "run with an error proc that throws an exception"
    setup do
      @proc_exception = Factory.exception
      error_proc = proc{ raise @proc_exception }
      Assert.stub(@daemon_data, :error_procs){ [error_proc] }

      @handler = @handler_class.new(@exception, @context_hash).tap(&:run)
    end
    subject{ @handler }

    should "set its exception to the exception thrown by the error proc" do
      assert_equal @proc_exception, subject.exception
    end

  end

  class RunWithMultipleErrorProcsThatThrowExceptionsTests < UnitTests
    desc "run with multiple error procs that throw an exception"
    setup do
      @first_caught_exception  = nil
      @second_caught_exception = nil
      @third_caught_exception  = nil

      @third_proc_exception = Factory.exception
      third_proc = proc do |exception, context|
        @third_caught_exception = exception
        raise @third_proc_exception
      end

      @second_proc_exception = Factory.exception
      second_proc = proc do |exception, context|
        @second_caught_exception = exception
        raise @second_proc_exception
      end

      first_proc = proc{ |exception, context| @first_caught_exception = exception }

      Assert.stub(@daemon_data, :error_procs){ [first_proc, second_proc, third_proc] }
      @handler = @handler_class.new(@exception, @context_hash).tap(&:run)
    end
    subject{ @handler }

    should "call each proc, passing the previously raised exception to the next" do
      assert_equal @exception,             @third_caught_exception
      assert_equal @third_proc_exception,  @second_caught_exception
      assert_equal @second_proc_exception, @first_caught_exception
    end

  end

  class ErrorContextTests < UnitTests
    desc "ErrorContext"
    setup do
      @context = Qs::ErrorContext.new(@context_hash)
    end
    subject{ @context }

    should have_readers :daemon_data
    should have_readers :queue_name, :serialized_payload
    should have_readers :job, :handler_class

    should "know its attributes" do
      assert_equal @context_hash[:daemon_data], subject.daemon_data
      exp = Qs::Queue::RedisKey.parse_name(@context_hash[:queue_redis_key])
      assert_equal exp, subject.queue_name
      assert_equal @context_hash[:serialized_payload], subject.serialized_payload
      assert_equal @context_hash[:job], subject.job
      assert_equal @context_hash[:handler_class], subject.handler_class
    end

    should "know if it equals another context" do
      exp = Qs::ErrorContext.new(@context_hash)
      assert_equal exp, subject

      exp = Qs::ErrorContext.new({})
      assert_not_equal exp, subject
    end

  end

end
