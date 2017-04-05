require 'assert'
require 'qs'

require 'test/support/app_queue'

class Qs::Queue

  class SystemTests < Assert::Context
    desc "Qs::Queue"
    setup do
      Qs.reset!
      @qs_test_mode = ENV['QS_TEST_MODE']
      ENV['QS_TEST_MODE'] = nil
      Qs.init

      @event = Qs::Event.new('qs-app', 'basic')
      @other_queue = Qs::Queue.new{ name(Factory.string) }
      @other_queue.event(@event.channel, @event.name, Factory.string)
    end
    teardown do
      Qs.redis.connection do |c|
        keys = c.keys('*qs-app*')
        c.pipelined{ keys.each{ |k| c.del(k) } }
      end
      Qs.reset!
      ENV['QS_TEST_MODE'] = @qs_test_mode
    end

  end

  class SyncSubscriptionsTests < SystemTests
    desc "sync_subscriptions"
    setup do
      AppQueue.sync_subscriptions
    end

    should "store subscriptions for the queue in redis" do
      AppQueue.event_route_names.each do |route_name|
        redis_key = Qs::Event::SubscribersRedisKey.new(route_name)
        smembers = Qs.redis.connection{ |c| c.smembers(redis_key) }
        assert_includes AppQueue.name, smembers
      end
    end

    should "allow adding a new queues subscriptions but preserve the existing" do
      @other_queue.sync_subscriptions

      smembers = Qs.redis.connection{ |c| c.smembers(@event.subscribers_redis_key) }
      assert_equal 2, smembers.size
      assert_includes AppQueue.name,     smembers
      assert_includes @other_queue.name, smembers
    end

    should "remove subscriptions if a queue no longer subscribes to the event" do
      route_names = AppQueue.event_route_names.reject{ |n| n == @event.route_name }
      Assert.stub(AppQueue, :event_route_names){ route_names }
      AppQueue.sync_subscriptions

      redis_key = Qs::Event.new('qs-app', 'basic').subscribers_redis_key
      smembers = Qs.redis.connection{ |c| c.smembers(redis_key) }
      assert_not_includes AppQueue.name, smembers
    end

  end

  class ClearSubscriptionsTests < SystemTests
    desc "clear_subscriptions"
    setup do
      AppQueue.sync_subscriptions
      @other_queue.sync_subscriptions
      AppQueue.clear_subscriptions
    end

    should "remove the queue from all of its events subscribers" do
      AppQueue.event_route_names.each do |route_name|
        redis_key = Qs::Event::SubscribersRedisKey.new(route_name)
        smembers = Qs.redis.connection{ |c| c.smembers(redis_key) }
        assert_not_includes AppQueue.name, smembers
      end

      smembers = Qs.redis.connection{ |c| c.smembers(@event.subscribers_redis_key) }
      assert_equal [@other_queue.name], smembers
    end

  end

end
