require 'assert'
require 'qs/event_handler_test_helpers'

require 'qs/event_handler'
require 'qs/job_test_runner'
require 'test/support/runner_spy'

module Qs::EventHandler::TestHelpers

  class UnitTests < Assert::Context
    desc "Qs::TestHelpers"
    setup do
      @test_helpers = Qs::EventHandler::TestHelpers
    end
    subject{ @test_helpers }

  end

  class MixinTests < UnitTests
    desc "as a mixin"
    setup do
      @handler_class = Class.new
      @args = { Factory.string => Factory.string }

      @runner_spy = nil
      Assert.stub(Qs::EventTestRunner, :new) do |*args|
        @runner_spy = RunnerSpy.new(*args)
      end

      context_class = Class.new{ include Qs::EventHandler::TestHelpers }
      @context = context_class.new
    end
    subject{ @context }

    should have_imeths :test_runner, :test_handler

    should "build an event test runner for a given handler using `test_runner`" do
      result = subject.test_runner(@handler_class, @args)

      assert_not_nil @runner_spy
      assert_equal @handler_class, @runner_spy.handler_class
      assert_equal @args, @runner_spy.args
      assert_equal @runner_spy, result
    end

    should "return an initialized handler instance using `test_handler`" do
      result = subject.test_handler(@handler_class, @args)

      assert_not_nil @runner_spy
      assert_equal @runner_spy.handler, result
    end

  end

end