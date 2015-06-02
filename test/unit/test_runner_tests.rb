require 'assert'
require 'qs/test_runner'

require 'qs'
require 'qs/event'

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
      @handler_class = TestMessageHandler
      @args = {
        :message => Factory.message,
        :params  => { Factory.string => Factory.string },
        :logger  => Factory.string,
        :flag    => Factory.boolean
      }
      @original_args = @args.dup
      @runner  = @runner_class.new(@handler_class, @args)
      @handler = @runner.handler
    end
    subject{ @runner }

    should have_imeths :run

    should "know its message, params and logger" do
      assert_equal @args[:message], subject.message
      assert_equal @args[:params],  subject.params
      assert_equal @args[:logger],  subject.logger
    end

    should "write extra args to its message handler" do
      assert_equal @args[:flag], @handler.flag
    end

    should "not alter the args passed to it" do
      assert_equal @original_args, @args
    end

    should "not call its message handler's before callbacks" do
      assert_nil @handler.before_called
    end

    should "call its message handler's init" do
      assert_true @handler.init_called
    end

    should "not run its message handler" do
      assert_nil @handler.run_called
    end

    should "not call its message handler's after callbacks" do
      assert_nil @handler.after_called
    end

    should "stringify and encode the params passed to it" do
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

  end

  class RunTests < InitTests
    desc "and run"
    setup do
      @runner.run
    end

    should "run its message handler" do
      assert_true @handler.run_called
    end

    should "not call its message handler's after callbacks" do
      assert_nil @handler.after_called
    end

  end

  class JobTestRunnerTests < UnitTests
    desc "JobTestRunner"
    setup do
      @runner_class = Qs::JobTestRunner
    end
    subject{ @runner_class }

    should "be a test runner" do
      assert_true subject < Qs::TestRunner
    end

  end

  class JobTestRunnerInitTests < JobTestRunnerTests
    desc "when init"
    setup do
      @handler_class = TestJobHandler
      @args = { :job => Factory.job }
      @original_args = @args.dup
      @runner = @runner_class.new(@handler_class, @args)
    end
    subject{ @runner }

    should "allow passing a job as its message" do
      assert_equal @args[:job], subject.message
    end

    should "use job over message if both are provided" do
      @args[:message] = Factory.message
      runner = @runner_class.new(@handler_class, @args)
      assert_equal @args[:job], runner.message
    end

    should "not alter the args passed to it" do
      assert_equal @original_args, @args
    end

    should "raise an invalid error when not passed a job handler" do
      assert_raises(Qs::InvalidJobHandlerError){ @runner_class.new(Class.new) }
    end

  end

  class EventTestRunnerTests < UnitTests
    desc "EventTestRunner"
    setup do
      @runner_class = Qs::EventTestRunner
    end
    subject{ @runner_class }

    should "be a test runner" do
      assert_true subject < Qs::TestRunner
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

    should "know its message and params" do
      exp_message = Qs::Event.build(
        @args[:event_channel],
        @args[:event_name],
        @args[:params],
        { :published_at => @args[:event_published_at] }
      ).job
      assert_equal exp_message,        subject.message
      assert_equal exp_message.params, subject.params
    end

    should "not alter the args passed to it" do
      assert_equal @original_args, @args
    end

    should "allow passing event params instead of params" do
      @args[:event_params] = @args[:params]
      @args.delete(:params)
      runner = @runner_class.new(@handler_class, @args)

      exp_message = Qs::Event.build(
        @args[:event_channel],
        @args[:event_name],
        @args[:event_params],
        { :published_at => @args[:event_published_at] }
      ).job
      assert_equal exp_message,        runner.message
      assert_equal exp_message.params, runner.params
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

    should "raise an invalid error when not passed an event handler" do
      assert_raises(Qs::InvalidEventHandlerError){ @runner_class.new(Class.new) }
    end

  end

  class TestMessageHandler
    include Qs::MessageHandler

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

  class TestJobHandler
    include Qs::JobHandler

  end

  class TestEventHandler
    include Qs::EventHandler

    public :event
  end

end
