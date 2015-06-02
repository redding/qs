require 'assert'
require 'qs/qs_runner'

require 'qs'
require 'qs/message_handler'

class Qs::QsRunner

  class UnitTests < Assert::Context
    desc "Qs::QsRunner"
    setup do
      Qs.config.timeout = Factory.integer
      @runner_class = Qs::QsRunner
    end
    teardown do
      Qs.reset!
      Qs.init
    end
    subject{ @runner_class }

    should "be a runner" do
      assert_true subject < Qs::Runner
    end

  end

  class InitTests < UnitTests
    desc "when init"
    setup do
      @handler_class = TestMessageHandler
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
      @timeout_called_with = nil
      Assert.stub(OptionalTimeout, :new) do |*args, &block|
        @timeout_called_with = args
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
      assert_equal [@runner.timeout], @timeout_called_with
    end

    should "run the handlers before callbacks" do
      assert_equal 1, @handler.first_before_call_order
      assert_equal 2, @handler.second_before_call_order
    end

    should "call the handlers init and run methods" do
      assert_equal 3, @handler.init_call_order
      assert_equal 4, @handler.run_call_order
    end

    should "run the handlers after callbacks" do
      assert_equal 5, @handler.first_after_call_order
      assert_equal 6, @handler.second_after_call_order
    end

  end

  class RunWithTimeoutErrorTests < RunSetupTests
    setup do
      Assert.stub(OptionalTimeout, :new){ raise Qs::TimeoutError }
    end

    should "raise a timeout error with a good message" do
      exception = nil
      begin; @runner.run; rescue StandardError => exception; end

      assert_kind_of Qs::TimeoutError, exception
      exp = "#{@handler_class} timed out (#{@runner.timeout}s)"
      assert_equal exp, exception.message
    end

  end

  class OptionalTimeoutTests < UnitTests
    desc "OptionalTimeout"
    setup do
      @timeout_called_with = nil
      Assert.stub(SystemTimer, :timeout_after) do |*args, &block|
        @timeout_called_with = args
        block.call
      end
    end
    subject{ OptionalTimeout }

    should have_imeths :new

    should "use a system timer timeout when provided a non-`nil` value" do
      value = Factory.integer
      block_run = false

      subject.new(value){ block_run = true }
      assert_equal [value, Qs::TimeoutError], @timeout_called_with
      assert_true block_run
    end

    should "call the block when provided a `nil` value" do
      block_run = false

      subject.new(nil){ block_run = true }
      assert_nil @timeout_called_with
      assert_true block_run
    end

  end

  class TestMessageHandler
    include Qs::MessageHandler

    attr_reader :first_before_call_order, :second_before_call_order
    attr_reader :first_after_call_order, :second_after_call_order
    attr_reader :init_call_order, :run_call_order
    attr_reader :response_data

    timeout Factory.integer

    before{ @first_before_call_order = next_call_order }
    before{ @second_before_call_order = next_call_order }

    after{ @first_after_call_order = next_call_order }
    after{ @second_after_call_order = next_call_order }

    def init!
      @init_call_order = next_call_order
    end

    def run!
      @run_call_order = next_call_order
    end

    private

    def next_call_order
      @order ||= 0
      @order += 1
    end
  end

end
