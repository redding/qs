require 'assert'
require 'qs/job_test_runner'

require 'qs'
require 'qs/event'

class Qs::JobTestRunner

  class UnitTests < Assert::Context
    desc "Qs::JobTestRunner"
    setup do
      Qs.init
      @runner_class = Qs::JobTestRunner
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
      @runner  = @runner_class.new(@handler_class, @args)
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

  class EventTestRunnerTests < UnitTests
    desc "EventTestRunner"
    setup do
      @runner_class = Qs::EventTestRunner
    end
    subject{ @runner_class }

    should "be a job test runner" do
      assert_true subject < Qs::JobTestRunner
    end

  end

  class EventTestRunnerInitTests < EventTestRunnerTests
    desc "when init"
    setup do
      @handler_class = TestEventHandler
      @args = {
        :event_channel      => Factory.string,
        :event_name         => Factory.string,
        :params             => { Factory.string => Factory.string },
        :event_published_at => Factory.string
      }
      @original_args = @args.dup
      @runner = @runner_class.new(@handler_class, @args)
    end
    subject{ @runner }

    should "know its job and params" do
      exp_job = Qs::Event.build(
        @args[:event_channel],
        @args[:event_name],
        @args[:params],
        @args[:event_published_at]
      ).job
      assert_equal exp_job,        subject.job
      assert_equal exp_job.params, subject.params
    end

    should "not alter the args passed to it" do
      assert_equal @original_args, @args
    end

    should "allow passing event params instead of params" do
      @args[:event_params] = @args[:params]
      @args.delete(:params)
      runner = @runner_class.new(@handler_class, @args)

      exp_job = Qs::Event.build(
        @args[:event_channel],
        @args[:event_name],
        @args[:event_params],
        { :published_at => @args[:event_published_at] }
      ).job
      assert_equal exp_job,        runner.job
      assert_equal exp_job.params, runner.params
    end

    should "default its event channel, name and params" do
      @args.delete(:event_channel)
      @args.delete(:event_name)
      @args.delete(:params)
      runner = nil
      assert_nothing_raised{ runner = @runner_class.new(@handler_class, @args) }
      handler = runner.handler
      assert_not_nil handler.event.channel
      assert_not_nil handler.event.name
      assert_equal({}, handler.event.params)
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

  class TestEventHandler
    include Qs::EventHandler

    public :event
  end

end
