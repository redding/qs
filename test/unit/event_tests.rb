require 'assert'
require 'qs/event'

class Qs::Event

  class BaseTests < Assert::Context
    desc "Qs::Event"
    setup do
      @event = Qs::Event.new('something', 'happened')
    end
    subject{ @event }

    should have_readers   :channel, :name, :args
    should have_accessors :publisher, :published_at
    should have_instance_methods :key, :validate!, :published?
    should have_class_method :from_job

    should "know its channel, name, and args" do
      assert_equal 'something', subject.channel
      assert_equal 'happened',  subject.name
      assert_equal Hash.new,    subject.args
    end

    should "have no publisher or published_at by default" do
      assert_empty subject.publisher
      assert_nil subject.published_at
    end

    should "be published if a published at is set" do
      subject.published_at = nil
      assert_equal false, subject.published?

      subject.published_at = Time.now
      assert_equal true, subject.published?
    end

    should "build its key from its channel and name" do
      assert_equal "#{subject.channel}:#{subject.name}", subject.key
    end

    should "know its job args representation" do
      exp_job_args_hash = {
        'channel'      => subject.channel,
        'event'        => subject.name,
        'args'         => subject.args,
        'publisher'    => subject.publisher,
        'published_at' => subject.published_at.to_i
      }
      assert_equal exp_job_args_hash, subject.to_job_args
    end

    # TODO should "use the distributor as its default job destination" do
    #   distrubutor_job = Qs::Job.new(*[
    #     Qs.distributor.queue_class,
    #     Qs.distributor.handler_class,
    #     subject.to_job_args
    #   ])

    #   assert_equal distrubutor_job, subject.to_job
    # end

    should "be able to override the job destination" do
      new_dest = Struct.new(:queue, :queue_class, :handler_class)
      a_new_dest = new_dest.new('a_queue', "A::QueueClass", "A::HandlerClass")
      new_dest_job = Qs::Job.new(*[
        a_new_dest.queue_class,
        a_new_dest.handler_class,
        subject.to_job_args
      ])

      assert_equal new_dest_job, subject.to_job(a_new_dest)
    end

  end

  class ValidationTests < BaseTests
    desc "when validating"
    setup do
      @published_at_time = Time.now
      @event.published_at = @published_at_time
    end

    should "validate if channel, name, and published_at are set" do
      assert_nothing_raised { subject.validate! }
    end

    should "raise an ArgumentError when validating without a channel or event" do
      assert_raises(ArgumentError) { Qs::Event.new(nil, nil).validate! }
    end

    should "raise an ArgumentError if no published_at value is set" do
      subject.published_at = nil
      assert_raises(ArgumentError) { subject.validate! }
    end

  end

  class FromJobTests < ValidationTests
    desc 'created given a job'
    setup do
      @new_event = Qs::Event.from_job(@event.to_job)
    end

    should "set its data correctly" do
      assert_equal subject.channel,   @new_event.channel
      assert_equal subject.name,      @new_event.name
      assert_equal subject.args,      @new_event.args
      assert_equal subject.publisher, @new_event.publisher
      assert_equal subject.published_at.to_i, @new_event.published_at.to_i
      assert_equal true, @new_event.published?
    end

  end

end
