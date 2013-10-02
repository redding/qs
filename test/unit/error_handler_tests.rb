require 'assert'
require 'qs/error_handler'

require 'qs/queue'

class Qs::ErrorHandler

  class UnitTests < Assert::Context
    desc "Qs::ErrorHandler"
    setup do
      @last_call = nil
      error_proc = proc{ |e, q, j| @last_call = ProcCall.new(e, q, j) }
      @queue = Qs::Queue.new
      @error_handler = Qs::ErrorHandler.new(@queue, [ error_proc ])
    end
    subject{ @error_handler }

    should have_imeths :run

    should "return the exception that it 'handled'" do
      exception = StandardError.new('test')
      returned_exception = subject.run(exception)
      assert_same exception, returned_exception
    end

    should "call the error proc passing the exception, queue and job" do
      exception = StandardError.new('test')
      job       = 'test'
      subject.run(exception, job)
      assert_not_nil @last_call
      assert_equal exception, @last_call.exception
      assert_equal @queue,    @last_call.queue
      assert_equal job,       @last_call.job
    end

  end

  class MultipleErrorProcTests < UnitTests
    desc "with multiple error procs"
    setup do
      @calls = []
      first_error_proc  = proc{ @calls << :first }
      second_error_proc = proc{ @calls << :second }
      @error_handler = Qs::ErrorHandler.new(@queue, [
        first_error_proc,
        second_error_proc
      ])
      @error_handler.run(StandardError.new)
    end

    should "call each error proc in order" do
      assert_equal [ :first, :second ], @calls
    end

  end

  class WithFailingErrorProcTests < UnitTests
    desc "when an error proc generates an exception"
    setup do
      @proc_exception = StandardError.new('not expected')
      first_error_proc  = proc{ raise(@proc_exception) }
      second_error_proc = proc{ |e, q, j| @caught_exception = e }
      @error_handler = Qs::ErrorHandler.new(@queue, [
        first_error_proc,
        second_error_proc
      ])
      @returned_exception = @error_handler.run(StandardError.new)
    end

    should "call the next error procs with the new exception" do
      assert_same @proc_exception, @caught_exception
    end

    should "return the exception last occurred" do
      assert_same @proc_exception, @returned_exception
    end

  end

  class WhenLastErrorProcFailsTests < UnitTests
    desc "when the last error proc generates an exception"
    setup do
      @proc_exception = StandardError.new('not expected')
      error_proc = proc{ |e, q, j| raise(@proc_exception) }
      @error_handler = Qs::ErrorHandler.new(@queue, [ error_proc ])
      @returned_exception = @error_handler.run(StandardError.new)
    end

    should "return the new exception" do
      assert_same @returned_exception, @proc_exception
    end

  end

  ProcCall = Struct.new(:exception, :queue, :job)

end
