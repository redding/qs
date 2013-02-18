require 'assert'
require 'qs/event'
require 'qs/event_handler'
require 'qs/test_helpers'

module Qs::EventHandler

  class BaseTests < Assert::Context
    include Qs::TestHelpers

    desc "Qs::EventHandler"
    setup do
      @handler_class = MyTestApp::EventHandlers::TestEvent
      @channel, @name, @args = 'a_channel', 'dat_event', {'dem' => 'args'}
      @handler = event_test_runner(@handler_class, @channel, @name, @args).handler
    end
    subject{ @handler }

    should have_readers :published_event

    should "set its published event to an instance of Event" do
      assert_instance_of Qs::Event, subject.published_event
    end

    should "set its published event based on given data" do
      assert_equal @channel, subject.published_event.channel
      assert_equal @name,    subject.published_event.name
      assert_equal @args,    subject.published_event.args
    end

    should "set the handler's args to the event args" do
      assert_equal(@args, subject.args.to_hash)
    end

  end

end
