require 'assert'
require 'qs/event_handler'

require 'much-plugin'
require 'qs'
require 'qs/message_handler'
require 'qs/test_runner'

module Qs::EventHandler

  class UnitTests < Assert::Context
    include Qs::EventHandler::TestHelpers

    desc "Qs::EventHandler"
    setup do
      Qs.init
      @handler_class = Class.new{ include Qs::EventHandler }
    end
    teardown do
      Qs.reset!
    end
    subject{ @handler_class }

    should "use much-plugin" do
      assert_includes MuchPlugin, Qs::Worker
    end

    should "be a message handler" do
      assert_includes Qs::MessageHandler, subject
    end

  end

  class InitTests < UnitTests
    desc "when init"
    setup do
      @event   = Factory.event
      @runner  = test_runner(TestEventHandler, :message => @event)
      @handler = @runner.handler
    end
    subject{ @handler }

    should "have private helpers for accessing event attrs" do
      assert_equal @event,              subject.instance_eval{ event }
      assert_equal @event.channel,      subject.instance_eval{ event_channel }
      assert_equal @event.name,         subject.instance_eval{ event_name }
      assert_equal @event.published_at, subject.instance_eval{ event_published_at }
    end

  end

  class TestHelpersTests < UnitTests
    desc "TestHelpers"
    setup do
      Qs.init
      event = Factory.event
      @args = {
        :message => event,
        :params  => event.params
      }

      context_class = Class.new{ include Qs::EventHandler::TestHelpers }
      @context = context_class.new
    end
    teardown do
      Qs.reset!
    end
    subject{ @context }

    should have_imeths :test_runner, :test_handler

    should "build a test runner for a given handler class" do
      runner = subject.test_runner(@handler_class, @args)

      assert_kind_of Qs::TestRunner, runner
      assert_equal @handler_class,   runner.handler_class
      assert_equal @args[:message],  runner.message
      assert_equal @args[:params],   runner.params
    end

    should "return an initialized handler instance" do
      handler = subject.test_handler(@handler_class, @args)
      assert_kind_of @handler_class, handler

      exp = subject.test_runner(@handler_class, @args).handler
      assert_equal exp, handler
    end

  end

  class TestEventHandler
    include Qs::EventHandler

  end

end
