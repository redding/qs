require 'assert'
require 'qs/dispatch_job'

require 'qs/event'
require 'qs/job'

class Qs::DispatchJob

  class UnitTests < Assert::Context
    desc "Qs::DispatchJob"
    setup do
      @job_class = Qs::DispatchJob
    end
    subject{ @job_class }

    should "be a job" do
      assert Qs::DispatchJob < Qs::Job
    end

  end

  class InitTests < UnitTests
    desc "when init"
    setup do
      @event_channel = Factory.string
      @event_name    = Factory.string
      @event_params  = { Factory.string => Factory.string }
      @created_at    = Factory.time
      @job = @job_class.new(@event_channel, @event_name, @event_params, {
        :created_at => @created_at
      })
    end
    subject{ @job }

    should have_imeths :event

    should "know its name, params and created at" do
      assert_equal Qs.dispatcher_job_name, subject.name
      exp = {
        'event_channel' => @event_channel,
        'event_name'    => @event_name,
        'event_params'  => @event_params
      }
      assert_equal exp, subject.params
      assert_equal @created_at, subject.created_at
    end

    should "know how to build an event from its params" do
      event = subject.event
      exp = Qs::Event.new(
        @event_channel,
        @event_name,
        @event_params,
        { :published_at => @created_at }
      )
      assert_equal exp, event
      assert_same event, subject.event
    end

  end

end
