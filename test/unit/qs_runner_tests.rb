require 'assert'
require 'qs/qs_runner'

require 'much-timeout'
require 'qs'
require 'qs/message_handler'

class Qs::QsRunner

  class UnitTests < Assert::Context
    desc "Qs::QsRunner"
    setup do
      Qs.config.timeout = Factory.integer
      @handler_class = TestMessageHandler
      @runner_class  = Qs::QsRunner
    end
    teardown do
      Qs.reset!
      Qs.init
    end
    subject{ @runner_class }

    should "be a runner" do
      assert_true subject < Qs::Runner
    end

    should "know its TimeoutInterrupt" do
      assert_true TimeoutInterrupt < Interrupt
    end

  end

  class InitTests < UnitTests
    desc "when init"
    setup do
      @runner = @runner_class.new(@handler_class)
    end
    subject{ @runner }

    should have_readers :timeout
    should have_imeths :run

    should "know its timeout" do
      assert_equal TestMessageHandler.timeout, subject.timeout
      handler_class = Class.new{ include Qs::MessageHandler }
      runner = @runner_class.new(handler_class)
      assert_equal Qs.config.timeout, runner.timeout
    end

  end

  class RunSetupTests < InitTests
    desc "and run"
    setup do
      @optional_timeout_called_with = nil
      Assert.stub(MuchTimeout, :optional_timeout) do |*args, &block|
        @optional_timeout_called_with = args
        block.call
      end
    end

  end

  class RunTests < RunSetupTests
    setup do
      @handler = @runner.handler
      @runner.run
    end

    should "run the handler in an optional timeout" do
      exp = [@runner.timeout, TimeoutInterrupt]
      assert_equal exp, @optional_timeout_called_with
    end

    should "run the handler's before callbacks" do
      assert_equal 1, @handler.first_before_call_order
      assert_equal 2, @handler.second_before_call_order
    end

    should "call the handler's init and run methods" do
      assert_equal 3, @handler.init_call_order
      assert_equal 4, @handler.run_call_order
    end

    should "run the handler's after callbacks" do
      assert_equal 5, @handler.first_after_call_order
      assert_equal 6, @handler.second_after_call_order
    end

  end

  class RunWithInitHaltTests < UnitTests
    desc "with a handler that halts on init"
    setup do
      @runner = @runner_class.new(@handler_class, :params => {
        'halt' => 'init'
      })
      @handler  = @runner.handler
      @response = @runner.run
    end
    subject{ @runner }

    should "run the before and after callbacks despite the halt" do
      assert_not_nil @handler.first_before_call_order
      assert_not_nil @handler.second_before_call_order
      assert_not_nil @handler.first_after_call_order
      assert_not_nil @handler.second_after_call_order
    end

    should "stop processing when the halt is called" do
      assert_not_nil @handler.init_call_order
      assert_nil @handler.run_call_order
    end

  end

  class RunWithRunHaltTests < UnitTests
    desc "when run with a handler that halts on run"
    setup do
      @runner = @runner_class.new(@handler_class, :params => {
        'halt' => 'run'
      })
      @handler  = @runner.handler
      @response = @runner.run
    end
    subject{ @runner }

    should "run the before and after callbacks despite the halt" do
      assert_not_nil @handler.first_before_call_order
      assert_not_nil @handler.second_before_call_order
      assert_not_nil @handler.first_after_call_order
      assert_not_nil @handler.second_after_call_order
    end

    should "stop processing when the halt is called" do
      assert_not_nil @handler.init_call_order
      assert_not_nil @handler.run_call_order
    end

  end

  class RunWithBeforeHaltTests < UnitTests
    desc "when run with a handler that halts in an after callback"
    setup do
      @runner = @runner_class.new(@handler_class, :params => {
        'halt' => 'before'
      })
      @handler  = @runner.handler
      @response = @runner.run
    end
    subject{ @runner }

    should "stop processing when the halt is called" do
      assert_not_nil @handler.first_before_call_order
      assert_nil @handler.second_before_call_order
    end

    should "not run the after callbacks b/c of the halt" do
      assert_nil @handler.first_after_call_order
      assert_nil @handler.second_after_call_order
    end

    should "not run the handler's init and run b/c of the halt" do
      assert_nil @handler.init_call_order
      assert_nil @handler.run_call_order
    end

  end

  class RunWithAfterHaltTests < UnitTests
    desc "when run with a handler that halts in an after callback"
    setup do
      @runner = @runner_class.new(@handler_class, :params => {
        'halt' => 'after'
      })
      @handler  = @runner.handler
      @response = @runner.run
    end
    subject{ @runner }

    should "run the before callback despite the halt" do
      assert_not_nil @handler.first_before_call_order
      assert_not_nil @handler.second_before_call_order
    end

    should "run the handler's init and run despite the halt" do
      assert_not_nil @handler.init_call_order
      assert_not_nil @handler.run_call_order
    end

    should "stop processing when the halt is called" do
      assert_not_nil @handler.first_after_call_order
      assert_nil @handler.second_after_call_order
    end

  end

  class RunWithTimeoutInterruptTests < RunSetupTests
    setup do
      Assert.stub(MuchTimeout, :optional_timeout){ raise TimeoutInterrupt }
    end

    should "raise a timeout error with a good message" do
      exception = assert_raises(Qs::TimeoutError) do
        @runner.run
      end

      exp = "#{@handler_class} timed out (#{@runner.timeout}s)"
      assert_equal exp, exception.message
    end

  end

  class TestMessageHandler
    include Qs::MessageHandler

    attr_reader :first_before_call_order, :second_before_call_order
    attr_reader :first_after_call_order, :second_after_call_order
    attr_reader :init_call_order, :run_call_order
    attr_reader :response_data

    timeout Factory.integer

    before{ @first_before_call_order = next_call_order; halt_if('before') }
    before{ @second_before_call_order = next_call_order }

    after{ @first_after_call_order = next_call_order; halt_if('after') }
    after{ @second_after_call_order = next_call_order }

    def init!
      @init_call_order = next_call_order
      halt_if('init')
    end

    def run!
      @run_call_order = next_call_order
      halt_if('run')
    end

    private

    def next_call_order; @order ||= 0; @order += 1; end

    def halt_if(value)
      halt if params['halt'] == value
    end

  end

end
