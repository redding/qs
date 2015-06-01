require 'assert'
require 'qs/job'

require 'qs/message'

class Qs::Job

  class UnitTests < Assert::Context
    desc "Qs::Job"
    setup do
      @name       = Factory.string
      @params     = { Factory.string => Factory.string }
      @created_at = Factory.time

      @job_class = Qs::Job
    end
    subject{ @job_class }

    should "know its payload type" do
      assert_equal 'job', PAYLOAD_TYPE
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

      @job = @job_class.new(@name, @params, :created_at => @created_at)
    end
    subject{ @job }

    should have_readers :name, :created_at
    should have_imeths :route_name

    should "know its attributes" do
      assert_equal PAYLOAD_TYPE, subject.payload_type
      assert_equal @name,         subject.name
      assert_equal @params,       subject.params
      assert_equal @created_at,   subject.created_at
    end

    should "default its created at to the current time" do
      job = @job_class.new(@name, @params)
      assert_equal @current_time, job.created_at
    end

    should "know its route name" do
      assert_same subject.name, subject.route_name
    end

    should "have a custom inspect" do
      reference = '0x0%x' % (subject.object_id << 1)
      exp = "#<Qs::Job:#{reference} " \
            "@name=#{subject.name.inspect} " \
            "@params=#{subject.params.inspect} " \
            "@created_at=#{subject.created_at.inspect}>"
      assert_equal exp, subject.inspect
    end

    should "be comparable" do
      matching = @job_class.new(@name, @params, {
        :created_at => @created_at
      })
      assert_equal matching, subject

      non_matching = @job_class.new(Factory.string, @params, {
        :created_at => @created_at
      })
      assert_not_equal non_matching, subject
      other_params = { Factory.string => Factory.string }
      non_matching = @job_class.new(@name, other_params, {
        :created_at => @created_at
      })
      assert_not_equal non_matching, subject
      non_matching = @job_class.new(@name, @params, {
        :created_at => Factory.time
      })
      assert_not_equal non_matching, subject
    end

    should "raise an error when given an invalid attributes" do
      assert_raises(Qs::BadJobError){ @job_class.new(nil, @params) }
      assert_raises(Qs::BadJobError){ @job_class.new(@name, nil) }
      assert_raises(Qs::BadJobError){ @job_class.new(@name, Factory.string) }
    end

  end

end
