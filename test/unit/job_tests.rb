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

    should have_imeths :parse

    should "know its payload type" do
      assert_equal 'job', PAYLOAD_TYPE
    end

    should "parse a job from a payload hash" do
      payload = {
        'type'       => @payload_type,
        'name'       => @name,
        'params'     => @params,
        'created_at' => @created_at.to_i
      }
      job = subject.parse(payload)
      assert_instance_of subject, job
      assert_equal payload['type'], job.payload_type
      assert_equal payload['name'], job.name
      assert_equal payload['params'], job.params
      assert_equal Time.at(payload['created_at']), job.created_at
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
    should have_imeths :route_name, :to_payload

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

    should "return a payload hash using `to_payload`" do
      exp = {
        'type'       => @payload_type,
        'name'       => @name,
        'params'     => @params,
        'created_at' => @created_at.to_i
      }
      assert_equal exp, subject.to_payload
    end

    should "sanitize its attributes with `to_payload`" do
      params = { Factory.string.to_sym => Factory.string }
      payload = @job_class.new(@name.to_sym, params, {
        :type       => @payload_type.to_sym,
        :created_at => @created_at
      }).to_payload

      assert_equal @payload_type, payload['type']
      assert_equal @name, payload['name']
      exp = StringifyParams.new(params)
      assert_equal exp, payload['params']
      assert_equal @created_at.to_i, payload['created_at']
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
      other_job = @job_class.new(@name, @params)
      Assert.stub(other_job, :to_payload){ subject.to_payload }
      assert_equal other_job, subject
      Assert.stub(other_job, :to_payload){ Hash.new }
      assert_not_equal other_job, subject
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

  class StringifyParamsTests < UnitTests
    desc "StringifyParams"
    subject{ StringifyParams }

    should have_imeths :new

    should "convert all hash keys to strings" do
      key, value = Factory.string.to_sym, Factory.string
      result = subject.new({
        key    => value,
        :hash  => { key => [value] },
        :array => [{ key => value }]
      })
      exp = {
        key.to_s => value,
        'hash'   => { key.to_s => [value] },
        'array'  => [{ key.to_s => value }]
      }
      assert_equal exp, result
    end

  end

end
