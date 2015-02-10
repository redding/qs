require 'assert'
require 'qs/test_helpers'

require 'qs/job_handler'
require 'test/support/runner_spy'

module Qs::TestHelpers

  class UnitTests < Assert::Context
    desc "Qs::TestHelpers"
    setup do
      @test_helpers = Qs::TestHelpers
    end
    subject{ @test_helpers }

  end

  class MixinTests < UnitTests
    desc "as a mixin"
    setup do
      context_class = Class.new{ include Qs::TestHelpers }
      @context = context_class.new
    end
    subject{ @context }

    should have_imeths :test_runner, :test_handler

  end

  class HandlerTestRunnerTests < MixinTests
    desc "for handler testing"
    setup do
      @handler_class = Class.new
      @args = { Factory.string => Factory.string }

      @runner_spy = nil
      Assert.stub(Qs::TestRunner, :new) do |*args|
        @runner_spy = RunnerSpy.new(*args)
      end
    end

    should "build a test runner for a given handler" do
      result = subject.test_runner(@handler_class, @args)

      assert_not_nil @runner_spy
      assert_equal @handler_class, @runner_spy.handler_class
      assert_equal @args, @runner_spy.args
      assert_equal @runner_spy, result
    end

    should "return an initialized handler instance" do
      result = subject.test_handler(@handler_class, @args)

      assert_not_nil @runner_spy
      assert_equal @runner_spy.handler, result
    end

  end

end

