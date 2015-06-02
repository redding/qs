require 'assert'
require 'qs/message'

class Qs::Message

  class UnitTests < Assert::Context
    desc "Qs::Message"
    setup do
      @payload_type  = Factory.string
      @params        = { Factory.string => Factory.string }
      @message_class = Qs::Message
    end
    subject{ @message_class }

  end

  class InitTests < UnitTests
    desc "when init"
    setup do
      @message = @message_class.new(@payload_type, @params)
    end
    subject{ @message }

    should have_readers :payload_type, :params
    should have_imeths :route_id, :route_name

    should "know its payload type and params" do
      assert_equal @payload_type, subject.payload_type
      assert_equal @params, subject.params
    end

    should "default its params" do
      message = @message_class.new(@payload_type)
      assert_equal({}, message.params)
    end

    should "know its route id" do
      route_name = Factory.string
      Assert.stub(subject, :route_name){ route_name }

      exp = RouteId.new(@payload_type, route_name)
      assert_equal exp, subject.route_id
    end

    should "raise a not implement error for its route name" do
      assert_raises(NotImplementedError){ subject.route_name }
    end

  end

  class RouteIdTests < UnitTests
    desc "RouteId"
    subject{ RouteId }

    should have_imeths :new

    should "build a route id given a payload type and a route name" do
      exp = "#{@payload_type}|#{@name}"
      assert_equal exp, subject.new(@payload_type, @name)
    end

  end

end
