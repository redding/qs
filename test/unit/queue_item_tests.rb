require 'assert'
require 'qs/queue_item'

require 'qs/queue'

class Qs::QueueItem

  class UnitTests < Assert::Context
    desc "Qs::QueueItem"
    setup do
      @queue_redis_key = Factory.string
      @encoded_payload = Factory.string
      @queue_item = Qs::QueueItem.new(@queue_redis_key, @encoded_payload)
    end
    subject{ @queue_item }

    should have_readers :queue_redis_key, :encoded_payload
    should have_accessors :started, :finished
    should have_accessors :message, :handler_class
    should have_accessors :exception, :time_taken

    should "know its queue redis key and encoded payload" do
      assert_equal @queue_redis_key, subject.queue_redis_key
      assert_equal @encoded_payload, subject.encoded_payload
    end

    should "defaults its other attributes" do
      assert_false subject.started
      assert_false subject.finished

      assert_nil subject.message
      assert_nil subject.handler_class
      assert_nil subject.exception
      assert_nil subject.time_taken
    end

    should "know if it equals another item" do
      exp = Qs::QueueItem.new(@queue_redis_key, @encoded_payload)
      assert_equal exp, subject

      redis_key = Qs::Queue::RedisKey.new(Factory.string)
      exp = Qs::QueueItem.new(redis_key, @encoded_payload)
      assert_not_equal exp, subject

      exp = Qs::QueueItem.new(@queue_redis_key, Factory.string)
      assert_not_equal exp, subject
    end

  end

end
