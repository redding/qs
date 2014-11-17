require 'assert'
require 'qs/error_handler'

require 'qs/daemon_data'
require 'qs/job'

class Qs::ErrorHandler

  class UnitTests < Assert::Context
    desc "Qs::ErrorHandler"
    setup do
      @exception = Factory.exception
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

      @daemon_data = Qs::DaemonData.new({
        :error_procs => [first_error_proc, second_error_proc]
      })
      @job = Qs::Job.new(Factory.string, Factory.string => Factory.string)
      @handler = @handler_class.new(@exception, @daemon_data, @job)
    end
    subject{ @handler }

    should have_readers :exception, :daemon_data, :job
    should have_imeths :run

    should "know its exception, daemon data and job" do
      assert_equal @exception, subject.exception
      assert_equal @daemon_data, subject.daemon_data
      assert_equal @job, subject.job
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

    should "pass its exception, daemon data and job to the error procs" do
      assert_not_nil @args_passed_to_error_proc
      assert_includes @exception, @args_passed_to_error_proc
      assert_includes @daemon_data, @args_passed_to_error_proc
      assert_includes @job, @args_passed_to_error_proc
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
      @daemon_data = Qs::DaemonData.new(:error_procs => [error_proc])

      @handler = @handler_class.new(@exception, @daemon_data).tap(&:run)
    end
    subject{ @handler }

    should "set its exception to the exception thrown by the error proc" do
      assert_equal @proc_exception, subject.exception
    end

  end

  class RunWithMultipleErrorProcsThatThrowExceptionsTests < UnitTests
    desc "run with multiple error procs that throw an exception"
    setup do
      @first_caught_exception = nil
      @second_caught_exception = nil
      @third_caught_exception = nil

      @third_proc_exception = Factory.exception
      third_proc = proc do |exception, d, j|
        @third_caught_exception = exception
        raise @third_proc_exception
      end

      @second_proc_exception = Factory.exception
      second_proc = proc do |exception, d, j|
        @second_caught_exception = exception
        raise @second_proc_exception
      end

      first_proc = proc{ |exception, d, j| @first_caught_exception = exception }

      @daemon_data = Qs::DaemonData.new({
        :error_procs => [first_proc, second_proc, third_proc]
      })
      @handler = @handler_class.new(@exception, @daemon_data).tap(&:run)
    end
    subject{ @handler }

    should "call each proc, passing the previously raised exception to the next" do
      assert_equal @exception, @third_caught_exception
      assert_equal @third_proc_exception, @second_caught_exception
      assert_equal @second_proc_exception, @first_caught_exception
    end

  end

end
