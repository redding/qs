require 'assert'
require 'qs/qs_runner'

require 'qs/job_handler'

class Qs::QsRunner

  class UnitTests < Assert::Context
    desc "Qs::QsRunner"
    setup do
      @runner_class = Qs::QsRunner
    end
    subject{ @runner_class }

    should "be a runner" do
      assert_true subject < Qs::Runner
    end

  end

  class InitTests < UnitTests
    desc "when init"
    setup do
      @handler_class = TestJobHandler
      @runner = @runner_class.new(@handler_class)
    end
    subject{ @runner }

    should have_imeths :run

  end

  class RunTests < InitTests
    desc "and run"
    setup do
      @handler = @runner.handler
      @runner.run
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

  class TestJobHandler
    include Qs::JobHandler

    attr_reader :first_before_call_order, :second_before_call_order
    attr_reader :first_after_call_order, :second_after_call_order
    attr_reader :init_call_order, :run_call_order
    attr_reader :response_data

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
