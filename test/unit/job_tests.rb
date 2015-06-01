require 'assert'
require 'qs/job'

class Qs::Job

  class UnitTests < Assert::Context
    desc "Qs::Job"
    setup do
      @payload_type = Factory.string
      @name         = Factory.string
      @params       = { Factory.string => Factory.string }
      @created_at   = Factory.time

      @job_class = Qs::Job
    end
    subject{ @job_class }

    should "know its payload type" do
      assert_equal 'job', PAYLOAD_TYPE
    end

  end

  class InitTests < UnitTests
    desc "when init"
    setup do
      @current_time = Factory.time
      Assert.stub(Time, :now).with{ @current_time }

      @job = @job_class.new(@name, @params, {
        :type       => @payload_type,
        :created_at => @created_at
      })
    end
    subject{ @job }

    should have_readers :payload_type, :name, :params, :created_at
    should have_imeths :route_name

    should "know its payload type, name, params and created at" do
      assert_equal @payload_type, subject.payload_type
      assert_equal @name,         subject.name
      assert_equal @params,       subject.params
      assert_equal @created_at,   subject.created_at
    end

    should "default its payload type and created at" do
      job = @job_class.new(@name, @params)
      assert_equal PAYLOAD_TYPE,  job.payload_type
      assert_equal @current_time, job.created_at
    end

    should "raise an error when given an invalid name or params" do
      assert_raises(Qs::BadJobError){ @job_class.new(nil, @params) }
      assert_raises(Qs::BadJobError){ @job_class.new(@name, nil) }
      assert_raises(Qs::BadJobError){ @job_class.new(@name, Factory.string) }
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
      matching_job = @job_class.new(@name, @params, {
        :type       => @payload_type,
        :created_at => @created_at
      })
      assert_equal matching_job, subject

      non_matching_job = @job_class.new(Factory.string, @params, {
        :type       => @payload_type,
        :created_at => @created_at
      })
      assert_not_equal non_matching_job, subject
      other_params = { Factory.string => Factory.string }
      non_matching_job = @job_class.new(@name, other_params, {
        :type       => @payload_type,
        :created_at => @created_at
      })
      assert_not_equal non_matching_job, subject
      non_matching_job = @job_class.new(@name, @params, {
        :type       => Factory.string,
        :created_at => @created_at
      })
      assert_not_equal non_matching_job, subject
      non_matching_job = @job_class.new(@name, @params, {
        :type       => @payload_type,
        :created_at => Factory.time
      })
      assert_not_equal non_matching_job, subject
    end

  end

  class RouteNameTests < UnitTests
    desc "RouteName"
    subject{ RouteName }

    should have_imeths :new

    should "build a route name given a payload type and name" do
      exp = "#{@payload_type}|#{@name}"
      assert_equal exp, RouteName.new(@payload_type, @name)
    end

  end



end
