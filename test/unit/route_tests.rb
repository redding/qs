require 'assert'
require 'qs/route'

require 'qs/daemon_data'
require 'qs/logger'
require 'test/support/runner_spy'

class Qs::Route

  class UnitTests < Assert::Context
    desc "Qs::Route"
    setup do
      @id = Factory.string
      @handler_class_name = TestHandler.to_s
      @route = Qs::Route.new(@id, @handler_class_name)
    end
    subject{ @route }

    should have_readers :id, :handler_class_name, :handler_class
    should have_imeths :validate!, :run

    should "know its id and handler class name" do
      assert_equal @id, subject.id
      assert_equal @handler_class_name, subject.handler_class_name
    end

    should "not know its handler class by default" do
      assert_nil subject.handler_class
    end

    should "constantize its handler class after being validated" do
      subject.validate!
      assert_equal TestHandler, subject.handler_class
    end

  end

  class RunTests < UnitTests
    desc "when run"
    setup do
      @message = Factory.message
      @daemon_data = Qs::DaemonData.new(:logger => Qs::NullLogger.new)

      @runner_spy = nil
      Assert.stub(Qs::QsRunner, :new) do |*args|
        @runner_spy = RunnerSpy.new(*args)
      end

      @route.run(@message, @daemon_data)
    end

    should "build and run a qs runner" do
      assert_not_nil @runner_spy
      assert_equal @route.handler_class, @runner_spy.handler_class
      exp = {
        :message => @message,
        :params  => @message.params,
        :logger  => @daemon_data.logger
      }
      assert_equal exp, @runner_spy.args
      assert_true @runner_spy.run_called
    end

  end

  class InvalidHandlerClassNameTests < UnitTests
    desc "with an invalid handler class name"
    setup do
      @route = Qs::Route.new(@name, Factory.string)
    end

    should "raise a no handler class error when validated" do
      assert_raises(Qs::NoHandlerClassError){ subject.validate! }
    end

  end

  TestHandler = Class.new

end
