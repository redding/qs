require 'assert'
require 'qs/event_handler'

require 'qs/event'
require 'qs/message_handler'

module Qs::EventHandler

  class UnitTests < Assert::Context
    desc "Qs::EventHandler"
    setup do
      @handler_class = Class.new{ include Qs::EventHandler }
    end
    subject{ @handler_class }

    should "be a message handler" do
      assert_includes Qs::MessageHandler, subject
    end

  end

  class InitTests < UnitTests
    desc "when init"
    setup do
      @runner  = FakeRunner.new
      @handler = TestEventHandler.new(@runner)
    end
    subject{ @handler }

    should "know its event, channel, name and published at" do
      assert_equal @runner.message,                   subject.public_event
      assert_equal subject.public_event.channel,      subject.public_event_channel
      assert_equal subject.public_event.name,         subject.public_event_name
      assert_equal subject.public_event.published_at, subject.public_event_published_at
    end

    should "have a custom inspect" do
      reference = '0x0%x' % (subject.object_id << 1)
      expected = "#<#{subject.class}:#{reference} " \
                 "@event=#{@handler.public_event.inspect}>"
      assert_equal expected, subject.inspect
    end

  end

  class TestEventHandler
    include Qs::EventHandler

    def public_event;              event;              end
    def public_event_channel;      event_channel;      end
    def public_event_name;         event_name;         end
    def public_event_published_at; event_published_at; end
  end

  class FakeRunner
    attr_accessor :message

    def initialize
      @message = Factory.event
    end
  end

end
