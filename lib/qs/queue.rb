require 'singleton'
require 'qs/job'
require 'qs/event'

module Qs

  JobNotConfiguredError   = Class.new(RuntimeError)
  JobHandlerMissingError  = Class.new(RuntimeError)
  JobHandlerNotFoundError = Class.new(RuntimeError)

  module Queue

    def self.included(klass)
      klass.class_eval do
        include Singleton
        extend  ClassMethods
      end
      Qs.register(klass)
    end

    # map singleton methods to the class level - a friendly singleton API

    module ClassMethods

      # can't rely on `method_missing` - everything responds to `name`
      define_method(:name) do |*args, &block|
        self.instance.send(:name, *args, &block)
      end

      def respond_to?(method)
        super || self.instance.respond_to?(method)
      end

      def method_missing(method, *args, &block)
        self.instance.send(method, *args, &block)
      end
    end

    attr_reader :job_handlers

    def initialize
      @job_handlers = {}
    end

    # Settings

    def redis_key; "#{Qs.config.queue_key_prefix}__#{self.name}"; end
    def logger; Qs.config.logger; end

    def name(value=nil)
      @name = value if !value.nil?
      @name || self.class.to_s
    end

    def job_handler_ns(value=nil)
      @job_handler_ns = value if !value.nil?
      @job_handler_ns
    end

    def event_handler_ns(value = nil)
      @event_handler_ns = value if !value.nil?
      @event_handler_ns
    end

    # This defines a named job and the handler to perform it with.

    def job(job_name, handler_class)
      if self.job_handler_ns && !(handler_class =~ /^::/)
        handler_class = "#{self.job_handler_ns}::#{handler_class}"
      end
      @job_handlers[job_name.to_s] = handler_class.to_s
    end

    # This defines a event and the handler to perform it with.

    def event(channel, event, handler_class)
      if self.event_handler_ns && !(handler_class =~ /^::/)
        handler_class = "#{self.event_handler_ns}::#{handler_class}"
      end

      Event.new(channel, event).tap do |event|
        self.subscriptions.set(event, handler_class)
      end
    end

    # Actions

    def add(job_name, args=nil)
      handler_class = @job_handlers[job_name.to_s]

      if handler_class
        job = Job.new(self.class, handler_class, args || {})
        self.enqueue(job)
      else
        raise JobNotConfiguredError, "There is no handler defined"\
                                     "for '#{job_name}' on `#{self.class}`."
      end
    end

    # Adapter actions

    def enqueue(job)
      raise NotImplementedError, 'use an adapter to get this behavior'
    end

    # Event subscription handling

    def subscriptions
      @subscriptions ||= Subscriptions.new(self)
    end

    def get_subscriptions;     self.subscriptions.to_hash; end
    def sync_subscriptions;    self.subscriptions.sync;    end
    def destroy_subscriptions; self.subscriptions.destroy; end
    def reset_subscriptions;   self.subscriptions.reset;   end

    # This utility manages a set of subscriptions for a queue and handles
    # accessing them in redis.

    class Subscriptions
      def initialize(queue)
        @queue_key   = queue.redis_key
        @queue_class = queue.class.to_s
        @platform    = Qs.config.platform
        @version     = Qs.config.version

        @queue_data  = Data.new(@queue_key)
        reset
      end

      def reset; @hash = {}; end
      def keys(*args);  @hash.keys(*args);  end
      def [](*args);    @hash.[](*args);    end
      def each(&block); @hash.each(&block); end
      def get(event); @hash[event.key]; end
      def set(event, handler_class); @hash[event.key] = handler_class; end
      def rm(event); @hash.delete(event.key); end

      def to_hash
        @queue_data.subscriptions_hash
      end

      def sync
        # set queue attributes
        @queue_data.set_queue_class @queue_class
        @queue_data.set_platform    @platform
        @queue_data.set_version     @version

        # make sure all current are added
        @hash.each do |event_key, handler_class|
          @queue_data.add_subscription(event_key, handler_class)
          @queue_data.add_subscriber(event_key, @queue_key)
        end

        # remove any that are not needed any more
        current_event_keys = @hash.keys
        not_needed = @queue_data.subscription_event_keys - current_event_keys
        not_needed.each do |event_key|
          @queue_data.rm_subscription(event_key)
          @queue_data.rm_subscriber(event_key, @queue_key)
        end
      end

      def destroy
        @queue_data.rm_queue_class
        @queue_data.rm_platform
        @queue_data.rm_version
        @queue_data.rm_subscriptions

        @hash.each do |event_key, handler_class|
          @queue_data.rm_subscriber(event_key, @queue_key)
        end
      end
    end

    class Data
      def initialize(queue_key)
        @queue_root_key = "queues:#{queue_key}"
      end

      def queue_class
        Qs.redis{ |c| c.get(queue_class_key) || '' }
      end
      def set_queue_class(klass)
        Qs.redis{ |c| c.set(queue_class_key, klass.to_s) }
      end
      def rm_queue_class
        Qs.redis{ |c| c.del(queue_class_key) }
      end

      def version
        VersionNum.new(Qs.redis{ |c| c.get(version_num_key) })
      end
      def set_version(num)
        Qs.redis{ |c| c.set(version_num_key, num.to_s) }
      end
      def rm_version
        Qs.redis{ |c| c.del(version_num_key) }
      end

      def platform
        Qs.redis{ |c| c.get(platform_key) || '' }
      end
      def set_platform(platform)
        Qs.redis{ |c| c.set(platform_key, platform.to_s) }
      end
      def rm_platform
        Qs.redis{ |c| c.del(platform_key) }
      end

      def handler_class(event_key);
        Qs.redis{ |c| c.hget(subscriptions_key, event_key) || '' }
      end

      def subscriptions_hash
        Qs.redis{ |c| c.hgetall(subscriptions_key) }
      end
      def subscription_event_keys
        Qs.redis{ |c| c.hkeys(subscriptions_key) }
      end
      def rm_subscriptions
        Qs.redis{ |c| c.del(subscriptions_key) }
      end

      def add_subscription(subscription, handler_class)
        Qs.redis{ |c| c.hset(subscriptions_key, subscription.to_s, handler_class.to_s) }
      end
      def rm_subscription(subscription)
        Qs.redis{ |c| c.hdel(subscriptions_key, subscription.to_s) }
      end

      def subscribers(event_key)
        Qs.redis{ |c| c.smembers(event_subscribers_key(event_key)) }
      end
      def add_subscriber(event_key, queue_key)
        Qs.redis{ |c| c.sadd(event_subscribers_key(event_key), queue_key.to_s) }
      end
      def rm_subscriber(event_key, queue_key)
        Qs.redis{ |c| c.srem(event_subscribers_key(event_key), queue_key.to_s) }
      end

      private

      def queue_class_key;   "#{@queue_root_key}:queue_class";   end
      def version_num_key;   "#{@queue_root_key}:version";       end
      def platform_key;      "#{@queue_root_key}:platform";      end
      def subscriptions_key; "#{@queue_root_key}:subscriptions"; end

      def event_subscribers_key(event_key)
        "events:#{event_key}:subscribers"
      end

      class VersionNum
        attr_reader :major, :minor, :patch, :special

        def initialize(version_string)
          @version = version_string || "0.0.0.0"
          @major, @minor, @patch, @special = @version.split('.').map(&:to_i)
        end

        def to_s; @version.to_s; end
      end
    end

  end

end
