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
    end
    subject{ Qs::Payload }

    should have_imeths :deserialize, :serialize
    should have_imeths :job, :job_hash
    should have_imeths :event, :event_hash

    should "serialize and deserialize messages" do
      message = Factory.message
      encoded_payload = subject.serialize(message)
      exp = Qs.encode(subject.send("#{message.payload_type}_hash", message))
      assert_equal exp, encoded_payload
      deserialized_job = subject.deserialize(encoded_payload)
      assert_equal message, deserialized_job
    end

    should "build jobs and job payload hashes" do
      job = Factory.job
      payload_hash = {
        'type'       => job.payload_type,
        'name'       => job.name,
        'params'     => job.params,
        'created_at' => Timestamp.new(job.created_at)
      }
      assert_equal job, subject.job(payload_hash)
      assert_equal payload_hash, subject.job_hash(job)
    end

    should "sanitize its jobs attributes when building a job payload hash" do
      job = Factory.job({
        :name   => Factory.string.to_sym,
        :params => { Factory.string.to_sym => Factory.string }
      })
      payload_hash = subject.job_hash(job)

      assert_equal job.name.to_s, payload_hash['name']
      exp = StringifyParams.new(job.params)
      assert_equal exp, payload_hash['params']
    end

    should "build events and event payload hashes" do
      event = Factory.event
      payload_hash = {
        'type'         => event.payload_type,
        'channel'      => event.channel,
        'name'         => event.name,
        'params'       => event.params,
        'published_at' => Timestamp.new(event.published_at)
      }
      assert_equal event, subject.event(payload_hash)
      assert_equal payload_hash, subject.event_hash(event)
    end

    should "sanitize its events attributes when building an event payload hash" do
      event = Factory.event({
        :channel => Factory.string.to_sym,
        :name    => Factory.string.to_sym,
        :params  => { Factory.string.to_sym => Factory.string }
      })
      payload_hash = subject.event_hash(event)

      assert_equal event.channel.to_s, payload_hash['channel']
      assert_equal event.name.to_s,    payload_hash['name']
      exp = StringifyParams.new(event.params)
      assert_equal exp, payload_hash['params']
    end

    should "raise errors for unknown parent types" do
      message = Factory.message
      Assert.stub(message, :payload_type){ Factory.string }
      payload_hash = { 'type' => message.payload_type }

      assert_raises(InvalidError){ subject.deserialize(payload_hash) }
      assert_raises(InvalidError){ subject.serialize(message) }
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

  class TimestampTests < UnitTests
    desc "Timestamp"
    subject{ Timestamp }

    should have_imeths :to_time, :new

    should "handle building timestamps and converting them to times" do
      time = Factory.time
      timestamp = subject.new(time)
      assert_equal time.to_i, timestamp
      assert_equal time, subject.to_time(timestamp)
    end

  end

end
