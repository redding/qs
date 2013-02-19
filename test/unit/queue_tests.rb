require 'assert'
require 'qs/event'
require 'qs/queue'

module Qs::Queue

  class BaseTests < Assert::Context
    desc "Qs::Queue"
    subject{ MyTestApp::TestQueue }

    should have_readers :job_handlers
    should have_imeths  :redis_key, :logger, :name
    should have_imeths  :job_handler_ns, :event_handler_ns
    should have_imeths  :job, :add, :enqueue
    should have_imeths  :subscriptions, :get_subscriptions, :sync_subscriptions
    should have_imeths  :destroy_subscriptions, :reset_subscriptions

    should "be a Singleton" do
      assert_includes Singleton, subject.included_modules
    end

    should "have added the queue to I-Resque known queues" do
      assert_includes subject, Qs.queues
    end

    should "have set it's name" do
      assert_equal 'test', subject.name
    end

    should "use the queue_key_prefix and its name to build its redis key" do
      assert_equal 'qs__test', subject.redis_key
    end

    should "add a handler mapping with the `job` method" do
      subject.job('test_job', 'TestJob')
      assert_equal 'TestJob', subject.job_handlers['test_job']
    end

    should "raise not implemented if `enqueue` has not been overwritten" do
      assert_raises(NotImplementedError){ subject.enqueue('a_job') }
    end

    should "create an return an Event using its params" do
      event = subject.event(:some, :event, "TestEvent")

      assert event
      assert_instance_of Qs::Event, event
      assert_equal 'some',  event.channel
      assert_equal 'event', event.name

      stored_handler_class = subject.subscriptions.get(event)
      assert_equal "TestEvent", stored_handler_class
    end

  end

  class JobWithNamespaceTests < BaseTests
    desc "job method with a defined job_handler_ns"
    subject{ MyTestApp::NamespacedTestQueue }

    should "add a handler mapping using the ns" do
      subject.job('namespaced_test_job', 'TestJob')
      assert_equal 'Some::TestJob', subject.job_handlers['namespaced_test_job']
    end

    should "ignore the ns when the handler class has leading colons" do
      subject.job('test_job', '::TestJob')
      assert_equal '::TestJob', subject.job_handlers['test_job']
    end

  end

  class EventWithNamespaceTests < BaseTests
    desc "event method with a defined event_handler_ns"
    subject{ MyTestApp::NamespacedTestQueue }

    should "add an event mapping using the event_handler_ns" do
      event = subject.event(:namespaced, :test_event, 'TestEvent')

      stored_handler = subject.subscriptions.get(event)
      assert_equal 'Some::TestEvent', stored_handler
    end

    should "ignore the handler ns when the handler class has leading colons" do
      event = subject.event(:other, :test_event, '::TestEvent')

      stored_handler = subject.subscriptions.get(event)
      assert_equal '::TestEvent', stored_handler
    end

  end

  class SyncTests < BaseTests
    desc "sync"
    setup do
      @queue_data  = Data.new(subject.redis_key)
      @some_event  = subject.event(:some_sync_test,  :event, 'SomeEvent')
      @other_event = subject.event(:other_sync_test, :event, 'OtherEvent')
      subject.sync_subscriptions
    end
    teardown do
      subject.subscriptions.rm(@some_event)
      subject.subscriptions.rm(@other_event)
      subject.sync_subscriptions
    end

    should "store the subscriptions in redis" do
      assert_equal 'MyTestApp::TestQueue', @queue_data.queue_class
      assert_equal 'ruby', @queue_data.platform
      assert_equal Qs::VERSION, @queue_data.version.to_s

      some_event_subscribers  = @queue_data.subscribers(@some_event.key)
      other_event_subscribers = @queue_data.subscribers(@other_event.key)

      assert_includes @some_event.key,  @queue_data.subscriptions_hash.keys
      assert_includes @other_event.key, @queue_data.subscriptions_hash.keys
      assert_includes 'qs__test', some_event_subscribers
      assert_includes 'qs__test', other_event_subscribers
    end

  end

  class SyncWithRemovalsTests < SyncTests
    desc "with removals"
    setup do
      subject.subscriptions.rm(@other_event)
      @another_event = subject.event(:another_sync_test, :event, 'AnotherEvent')
      subject.sync_subscriptions
    end
    teardown do
      subject.subscriptions.rm(@other_event)
      subject.sync_subscriptions
    end

    should "sync subscriptions by adding new ones and removing old ones" do
      another_event_subscribers = @queue_data.subscribers(@another_event.key)
      other_event_subscribers   = @queue_data.subscribers(@other_event.key)

      assert_includes @another_event.key, @queue_data.subscriptions_hash.keys
      assert_not_includes @other_event.key, @queue_data.subscriptions_hash.keys
      assert_includes     'qs__test', another_event_subscribers
      assert_not_includes 'qs__test', other_event_subscribers
    end

  end

  class DestroyTests < SyncTests
    desc "then destroy"
    setup do
      subject.destroy_subscriptions
    end
    teardown do
      subject.sync_subscriptions
    end

    should "destroy all the subscriptions in redis" do
      assert_not_equal 'TestQueue', @queue_data.queue_class
      assert_not_equal 'ruby',      @queue_data.platform
      assert_not_equal Qs::VERSION, @queue_data.version.to_s

      assert_equal Hash.new, @queue_data.subscriptions_hash

      some_event_subscribers  = @queue_data.subscribers(@some_event.key)
      other_event_subscribers = @queue_data.subscribers(@other_event.key)

      assert_not_includes 'i-events__test', some_event_subscribers
      assert_not_includes 'i-events__test', other_event_subscribers
    end

  end

end
