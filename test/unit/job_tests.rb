require 'assert'
require 'qs/job'

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

    should have_imeths :parse

    should "parse a job from a payload hash" do
      payload = {
        'name'       => @name,
        'params'     => @params,
        'created_at' => @created_at.to_i
      }
      job = subject.parse(payload)
      assert_instance_of subject, job
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

      @job = @job_class.new(@name, @params, @created_at)
    end
    subject{ @job }

    should have_readers :name, :params, :created_at
    should have_imeths :to_payload

    should "know its name, params and created at" do
      assert_equal @name,       subject.name
      assert_equal @params,     subject.params
      assert_equal @created_at, subject.created_at
    end

    should "default its created at" do
      job = @job_class.new(@name, @params)
      assert_equal @current_time, job.created_at
    end

    should "return a payload hash using `to_payload`" do
      payload_hash = subject.to_payload
      expected = {
        'name'       => @name,
        'params'     => @params,
        'created_at' => @created_at.to_i
      }
      assert_equal expected, payload_hash
    end

    should "convert job names to strings using `to_payload`" do
      job = @job_class.new(@name.to_sym, @params)
      assert_equal @name, job.to_payload['name']
    end

    should "convert params keys to strings using `to_payload`" do
      params = {
        :basic    => Factory.string,
        :in_array => [ { :test => Factory.string } ],
        :nested   => { :test => Factory.string }
      }
      job = @job_class.new(@name, params)
      expected = {
        'basic'    => params[:basic],
        'in_array' => [ { 'test' => params[:in_array].first[:test] } ],
        'nested'   => { 'test' => params[:nested][:test] }
      }
      assert_equal expected, job.to_payload['params']
    end

    should "raise an error when given an invalid name or params" do
      assert_raises(Qs::BadJobError){ @job_class.new(nil, @params) }
      assert_raises(Qs::BadJobError){ @job_class.new(@name, nil) }
      assert_raises(Qs::BadJobError){ @job_class.new(@name, Factory.string) }
    end

    should "have a custom inspect" do
      reference = '0x0%x' % (subject.object_id << 1)
      expected = "#<Qs::Job:#{reference} " \
                 "@name=#{subject.name.inspect} " \
                 "@params=#{subject.params.inspect} " \
                 "@created_at=#{subject.created_at.inspect}>"
      assert_equal expected, subject.inspect
    end

    should "be comparable" do
      matching = @job_class.new(@name, @params, @created_at)
      assert_equal matching, subject
      non_matching = @job_class.new(Factory.string, @params, @created_at)
      assert_not_equal non_matching, subject
      params = { Factory.string => Factory.string }
      non_matching = @job_class.new(@name, params, @created_at)
      assert_not_equal non_matching, subject
      non_matching = @job_class.new(@name, @params, Factory.time)
      assert_not_equal non_matching, subject
    end

  end

end
