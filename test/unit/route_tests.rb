require 'assert'
require 'qs/route'

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
