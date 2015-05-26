require 'assert'
require 'qs/event'

require 'qs/job'

class Qs::Event

  class UnitTests < Assert::Context
    desc "Qs::Event"
    setup do
      @channel      = Factory.string
      @name         = Factory.string
      @params       = { Factory.string => Factory.string }
      @published_at = Factory.time

      @event_class = Qs::Event
    end
    subject{ @event_class }

    should have_imeths :build

    should "know its payload type" do
      assert_equal 'event', PAYLOAD_TYPE
    end

    should "build an event from args" do
      event = subject.build(@channel, @name, @params, {
        :published_at => @published_at
      })
      job = event.job

      assert_instance_of Qs::Job, job
      assert_equal PAYLOAD_TYPE, job.payload_type
      assert_equal Qs::Event::JobName.new(@channel, @name), job.name
      exp = {
        'event_channel' => @channel,
        'event_name'    => @name,
        'event_params'  => @params
      }
      assert_equal exp, job.params
      assert_equal @published_at, job.created_at
    end

  end

  class InitTests < UnitTests
    desc "when init"
    setup do
      @job_params = {
        'event_channel' => @channel,
        'event_name'    => @name,
        'event_params'  => @params
      }
      @job = Qs::Job.new(Factory.string, @job_params)

      @event = @event_class.new(@job)
    end
    subject{ @event }

    should have_readers :job
    should have_imeths :channel, :name, :params, :published_at

    should "know its job" do
      assert_equal @job, subject.job
    end

    should "know its channel, name, params and published at" do
      assert_equal @job.params['event_channel'], subject.channel
      assert_equal @job.params['event_name'],    subject.name
      assert_equal @job.params['event_params'],  subject.params
      assert_equal @job.created_at,              subject.published_at
    end

    should "raise an error when given an invalid job" do
      job_params = @job_params.dup
      job_params.delete('event_channel')
      job = Qs::Job.new(Factory.string, job_params)
      assert_raises(Qs::BadEventError){ @event_class.new(job) }

      job_params = @job_params.dup
      job_params.delete('event_name')
      job = Qs::Job.new(Factory.string, job_params)
      assert_raises(Qs::BadEventError){ @event_class.new(job) }

      job_params = @job_params.dup
      job_params.delete('event_params')
      job = Qs::Job.new(Factory.string, job_params)
      assert_raises(Qs::BadEventError){ @event_class.new(job) }
    end

    should "have a custom inspect" do
      reference = '0x0%x' % (subject.object_id << 1)
      expected = "#<Qs::Event:#{reference} " \
                 "@channel=#{subject.channel.inspect} " \
                 "@name=#{subject.name.inspect} " \
                 "@params=#{subject.params.inspect} " \
                 "@published_at=#{subject.published_at.inspect}>"
      assert_equal expected, subject.inspect
    end

    should "be comparable" do
      other_job   = Qs::Job.new(Factory.string, @job_params)
      other_event = @event_class.new(other_job)

      Assert.stub(other_job, :==).with(subject.job){ true }
      assert_equal other_event, subject
      Assert.stub(other_job, :==).with(subject.job){ false }
      assert_not_equal other_event, subject
    end

  end

  class JobNameTests < UnitTests
    desc "JobName"
    subject{ JobName }

    should have_imeths :new

    should "return an event job name given an event channel and event name" do
      assert_equal "#{@channel}:#{@name}", subject.new(@channel, @name)
    end

  end

end
