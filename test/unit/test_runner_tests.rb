require 'assert'
require 'qs/test_runner'

require 'qs'

class Qs::TestRunner

  class UnitTests < Assert::Context
    desc "Qs::TestRunner"
    setup do
      Qs.init
      @runner_class = Qs::TestRunner
    end
    teardown do
      Qs.reset!
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
      @args = {
        :job    => Factory.string,
        :params => { Factory.string => Factory.string },
        :logger => Factory.string,
        :flag   => Factory.boolean
      }
      @original_args = @args.dup
      @runner = @runner_class.new(@handler_class, @args)
      @handler = @runner.handler
    end
    subject{ @runner }

    should have_imeths :run

    should "know its job, params and logger" do
      assert_equal @args[:job], subject.job
      assert_equal @args[:params], subject.params
      assert_equal @args[:logger], subject.logger
    end

    should "write extra args to its job handler" do
      assert_equal @args[:flag], @handler.flag
    end

    should "not alter the args passed to it" do
      assert_equal @original_args, @args
    end

    should "not call its job handler's before callbacks" do
      assert_nil @handler.before_called
    end

    should "call its job handler's init" do
      assert_true @handler.init_called
    end

    should "not run its job handler" do
      assert_nil @handler.run_called
    end

    should "not call its job handler's after callbacks" do
      assert_nil @handler.after_called
    end

    should "stringify and serialize the params passed to it" do
      key, value = Factory.string.to_sym, Factory.string
      params = {
        key    => value,
        'date' => Date.today
      }
      runner = @runner_class.new(@handler_class, :params => params)
      exp = {
        key.to_s => value,
        'date'   => params['date'].to_s
      }
      assert_equal exp, runner.params
    end

    should "raise an invalid error when not passed a job handler" do
      assert_raises(Qs::InvalidJobHandlerError){ @runner_class.new(Class.new) }
    end

  end

  class RunTests < InitTests
    desc "and run"
    setup do
      @runner.run
    end

    should "run its job handler" do
      assert_true @handler.run_called
    end

    should "not call its job handler's after callbacks" do
      assert_nil @handler.after_called
    end

  end

  class TestJobHandler
    include Qs::JobHandler

    attr_reader :before_called, :after_called
    attr_reader :init_called, :run_called
    attr_accessor :flag

    before{ @before_called = true }
    after{ @after_called = true }

    def init!
      @init_called = true
    end

    def run!
      @run_called = true
    end
  end

end
