require 'assert'
require 'qs/queue'

# These system tests ensure the action methods on a QueueSet correctly manage
# the persisted subscriptions for all the queues in the set.

class QueueSetActionsTests < Assert::Context
  desc "the QueueSet action"
  setup do
    @queues = Qs.queues
    @output = Output.new

    # sync and clear output messages to start with a known state
    @queues.sync_subscriptions(@output)
    @output.msgs.clear
  end

  def subscriptions_msg(queue); "#{queue} (#{queue.redis_key}) subscriptions:"; end
  def assert_msg_outputted(msg); assert_includes msg, @output.normalized_msgs; end

  class Output
    attr_reader :msgs
    def initialize; @msgs = [];      end
    def puts(msg);  @msgs.push(msg); end
    def normalized_msgs
      # clean the messages of any extra spaces, they get in the way when
      # comparing actual and expected strings
      @msgs.map{|m| m.gsub(/\s+/, ' ').strip}
    end
  end

  class ListActionTests < QueueSetActionsTests
    desc "for listing subscriptions"
    setup do
      @queues.list_subscriptions(@output)
    end

    should "output queue subscriptions" do
      @queues.first.tap do |queue|
        assert_msg_outputted subscriptions_msg(queue)
        queue.subscriptions.keys.first.tap do |event_key|
          handler_class = queue.subscriptions[event_key]
          assert_msg_outputted "#{event_key} => #{handler_class}"
        end
      end
    end

  end

  class SyncActionTests < QueueSetActionsTests
    desc "for syncing subscriptions"
    setup do
      @queues.sync_subscriptions(@output)
    end

    should "output that it is syncing subscriptions for all queues" do
      assert_msg_outputted "Syncing subscriptions for all queues..."
    end

    should "run the list task" do
      @queues.each{|q| assert_msg_outputted subscriptions_msg(q)}
    end

    should "store the queue subscriptions in redis" do
      @queues.first.tap do |queue|
        queue_data = Qs::Queue::Data.new(queue.redis_key)

        assert_equal queue.to_s,         queue_data.queue_class
        assert_equal Qs.config.platform, queue_data.platform
        assert_equal Qs.config.version,  queue_data.version.to_s

        queue.subscriptions.keys.first.tap do |event_key|
          handler_class = queue.subscriptions[event_key]
          assert_equal    handler_class,   queue_data.handler_class(event_key)
          assert_includes queue.redis_key, queue_data.subscribers(event_key)
        end
      end
    end

  end

  class DestroyActionTests < QueueSetActionsTests
    desc "for removing subscriptions"
    setup do
      @queues.destroy_subscriptions(@output)
    end

    should "output that it is syncing subscriptions for all queues" do
      assert_msg_outputted "Removing subscriptions for all queues..."
    end

    should "run the list task" do
      @queues.each{|q| assert_msg_outputted subscriptions_msg(q)}
    end

    should "have removed the queues configuration from redis" do
      @queues.first.tap do |queue|
        queue_data = Qs::Queue::Data.new(queue.redis_key)

        assert_not_equal queue.to_s,         queue_data.queue_class
        assert_not_equal Qs.config.platform, queue_data.platform
        assert_not_equal Qs.config.version,  queue_data.version.to_s

        queue.subscriptions.keys.first.tap do |event_key|
          handler_class = queue.subscriptions[event_key]
          assert_not_equal    handler_class,   queue_data.handler_class(event_key)
          assert_not_includes queue.redis_key, queue_data.subscribers(event_key)
        end
      end
    end

  end

end
