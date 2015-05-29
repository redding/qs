require 'assert'
require 'qs/redis_item'

require 'qs/queue'

class Qs::RedisItem

  class UnitTests < Assert::Context
    desc "Qs::RedisItem"
    setup do
      @queue_redis_key = Factory.string
      @encoded_payload = Factory.string
      @redis_item = Qs::RedisItem.new(@queue_redis_key, @encoded_payload)
    end
    subject{ @redis_item }

    should have_readers :queue_redis_key, :encoded_payload
    should have_accessors :started, :finished
    should have_accessors :job, :handler_class
    should have_accessors :exception, :time_taken

    should "know its queue redis key and encoded payload" do
      assert_equal @queue_redis_key, subject.queue_redis_key
      assert_equal @encoded_payload, subject.encoded_payload
    end

    should "defaults its other attributes" do
      assert_false subject.started
      assert_false subject.finished

      assert_nil subject.job
      assert_nil subject.handler_class
      assert_nil subject.exception
      assert_nil subject.time_taken
    end

    should "know if it equals another item" do
      exp = Qs::RedisItem.new(@queue_redis_key, @encoded_payload)
      assert_equal exp, subject

      redis_key = Qs::Queue::RedisKey.new(Factory.string)
      exp = Qs::RedisItem.new(redis_key, @encoded_payload)
      assert_not_equal exp, subject

      exp = Qs::RedisItem.new(@queue_redis_key, Factory.string)
      assert_not_equal exp, subject
    end

  end

end
