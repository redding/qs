require 'assert'
require 'qs/event'

require 'qs/message'

class Qs::Event

  class UnitTests < Assert::Context
    desc "Qs::Event"
    setup do
      @channel      = Factory.string
      @name         = Factory.string
      @params       = { Factory.string => Factory.string }
      @publisher    = Factory.string
      @published_at = Factory.time

      @event_class = Qs::Event
    end
    subject{ @event_class }

    should "know its payload type" do
      assert_equal 'event', PAYLOAD_TYPE
    end

    should "be a message" do
      assert subject < Qs::Message
    end

  end

  class InitTests < UnitTests
    desc "when init"
    setup do
      @current_time = Factory.time
      Assert.stub(Time, :now).with{ @current_time }

      @event = @event_class.new(@channel, @name, @params, {
        :publisher    => @publisher,
        :published_at => @published_at
      })
    end
    subject{ @event }

    should have_readers :channel, :name, :publisher, :published_at
    should have_imeths :route_name

    should "know its attributes" do
      assert_equal PAYLOAD_TYPE,  subject.payload_type
      assert_equal @channel,      subject.channel
      assert_equal @name,         subject.name
      assert_equal @params,       subject.params
      assert_equal @publisher,    subject.publisher
      assert_equal @published_at, subject.published_at
    end

    should "default its published at to the current time" do
      event = @event_class.new(@channel, @name, @params)
      assert_equal @current_time, event.published_at
    end

    should "know its route name" do
      exp = RouteName.new(@channel, @name)
      result = subject.route_name
      assert_equal exp, result
      assert_same result, subject.route_name
    end

    should "have a custom inspect" do
      reference = '0x0%x' % (subject.object_id << 1)
      exp = "#<Qs::Event:#{reference} " \
            "@channel=#{subject.channel.inspect} " \
            "@name=#{subject.name.inspect} " \
            "@params=#{subject.params.inspect} " \
            "@publisher=#{subject.publisher.inspect} " \
            "@published_at=#{subject.published_at.inspect}>"
      assert_equal exp, subject.inspect
    end

    should "be comparable" do
      matching = @event_class.new(@channel, @name, @params, {
        :publisher    => @publisher,
        :published_at => @published_at
      })
      assert_equal matching, subject

      non_matching = @event_class.new(Factory.string, @name, @params, {
        :publisher    => @publisher,
        :published_at => @published_at
      })
      assert_not_equal non_matching, subject
      non_matching = @event_class.new(@channel, Factory.string, @params, {
        :publisher    => @publisher,
        :published_at => @published_at
      })
      assert_not_equal non_matching, subject
      other_params = { Factory.string => Factory.string }
      non_matching = @event_class.new(@channel, @name, other_params, {
        :publisher    => @publisher,
        :published_at => @published_at
      })
      assert_not_equal non_matching, subject
      non_matching = @event_class.new(@channel, @name, @params, {
        :publisher    => Factory.string,
        :published_at => @published_at
      })
      assert_not_equal non_matching, subject
      non_matching = @event_class.new(@channel, @name, @params, {
        :publisher    => @publisher,
        :published_at => Factory.time
      })
      assert_not_equal non_matching, subject
    end

    should "raise an error when given invalid attributes" do
      assert_raises(Qs::BadEventError){ @event_class.new(nil, @name, @params) }
      assert_raises(Qs::BadEventError) do
        @event_class.new(@channel, nil, @params)
      end
      assert_raises(Qs::BadEventError) do
        @event_class.new(@channel, @name, Factory.string)
      end
      assert_raises(Qs::BadEventError){ @event_class.new(@channel, @name, nil) }
    end

  end

  class RouteNameTests < UnitTests
    desc "RouteName"
    subject{ RouteName }

    should have_imeths :new

    should "return an event route name given an event channel and event name" do
      assert_equal "#{@channel}:#{@name}", subject.new(@channel, @name)
    end

  end

  class SubscribersRedisKeyTests < UnitTests
    desc "SubscribersRedisKey"
    subject{ SubscribersRedisKey }

    should have_imeths :new

    should "return an event subscribers redis key given an event route name" do
      event_route_name = RouteName.new(@channel, @name)
      exp = "events:#{event_route_name}:subscribers"
      assert_equal exp, subject.new(event_route_name)
    end

  end

end
