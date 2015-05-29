require 'assert'
require 'qs/payload'

module Qs::Payload

  class UnitTests < Assert::Context
    desc "Qs::Payload"
    setup do
      # the default JSON encoder/decoder is not deterministic, the keys in the
      # string can be randomly ordered
      Assert.stub(Qs, :encode){ |hash| hash.to_a.sort }
      Assert.stub(Qs, :decode){ |array| Hash[array] }

      @job = Factory.job
    end
    subject{ Qs::Payload }

    should have_imeths :deserialize, :job
    should have_imeths :serialize, :job_hash

    should "serialize and deserialize jobs" do
      encoded_payload = subject.serialize(@job)
      exp = Qs.encode(subject.job_hash(@job))
      assert_equal exp, encoded_payload
      deserialized_job = subject.deserialize(encoded_payload)
      assert_equal @job, deserialized_job
    end

    should "build jobs and payload hashes" do
      payload_hash = {
        'type'       => @job.payload_type,
        'name'       => @job.name,
        'params'     => @job.params,
        'created_at' => @job.created_at.to_i
      }
      assert_equal @job, subject.job(payload_hash)
      assert_equal payload_hash, subject.job_hash(@job)
    end

    should "sanitize its jobs attributes when building a payload hash" do
      job = Factory.job({
        :type   => Factory.string.to_sym,
        :name   => Factory.string.to_sym,
        :params => { Factory.string.to_sym => Factory.string }
      })
      payload_hash = subject.job_hash(job)

      assert_equal job.payload_type.to_s, payload_hash['type']
      assert_equal job.name.to_s, payload_hash['name']
      exp = StringifyParams.new(job.params)
      assert_equal exp, payload_hash['params']
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
