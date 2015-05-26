require 'assert'
require 'qs/event_handler'

require 'qs/event'
require 'qs/job_handler'

module Qs::EventHandler

  class UnitTests < Assert::Context
    desc "Qs::EventHandler"
    setup do
      @handler_class = Class.new{ include Qs::EventHandler }
    end
    subject{ @handler_class }

    should "be a job handler" do
      assert_includes Qs::JobHandler, subject
    end

  end

  class InitTests < UnitTests
    desc "when init"
    setup do
      @runner  = FakeRunner.new
      @handler = TestEventHandler.new(@runner)
    end
    subject{ @handler }

    should "know its event and params" do
      event = Qs::Event.new(@runner.job)
      assert_equal event,        subject.public_event
      assert_equal event.params, subject.public_params
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

    def public_params; params; end
    def public_event;  event;  end
  end

  class FakeRunner
    attr_accessor :job

    def initialize
      @job = Factory.event_job
    end
  end

end