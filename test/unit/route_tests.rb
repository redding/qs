require 'assert'
require 'qs/route'

require 'qs/daemon_data'
require 'qs/logger'
require 'qs/job'

class Qs::Route

  class UnitTests < Assert::Context
    desc "Qs::Route"
    setup do
      @name = Factory.string
      @handler_class_name = TestHandler.to_s
      @route = Qs::Route.new(@name, @handler_class_name)
    end
    subject{ @route }

    should have_readers :name, :handler_class_name, :handler_class
    should have_imeths :validate!, :run

    should "know its name and handler class name" do
      assert_equal @name, subject.name
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
      @job = Qs::Job.new(Factory.string, Factory.string => Factory.string)
      @daemon_data = Qs::DaemonData.new(:logger => Qs::NullLogger.new)

      @runner_spy = RunnerSpy.new
      Assert.stub(Qs::QsRunner, :new) do |handler_class, args|
        @runner_spy.handler_class = handler_class
        @runner_spy.args = args
        @runner_spy
      end

      @route.run(@job, @daemon_data)
    end

    should "build and run a qs runner" do
      assert_equal @route.handler_class, @runner_spy.handler_class
      expected = {
        :job    => @job,
        :params => @job.params,
        :logger => @daemon_data.logger
      }
      assert_equal expected, @runner_spy.args
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

  class RunnerSpy
    attr_accessor :handler_class, :args
    attr_reader :run_called

    def initialize
      @run_called = false
    end

    def run
      @run_called = true
    end
  end

end