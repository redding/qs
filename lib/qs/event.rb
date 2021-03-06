require 'qs/message'

module Qs

  class Event < Message

    PAYLOAD_TYPE = 'event'

    attr_reader :channel, :name, :publisher, :published_at

    def initialize(channel, name, options = nil)
      options ||= {}
      options[:params] ||= {}
      validate!(channel, name, options[:params])
      @channel      = channel
      @name         = name
      @publisher    = options[:publisher]
      @published_at = options[:published_at] || Time.now
      super(PAYLOAD_TYPE, options)
    end

    def route_name
      @route_name ||= Event::RouteName.new(self.channel, self.name)
    end

    def subscribers_redis_key
      @subscribers_redis_key ||= SubscribersRedisKey.new(self.route_name)
    end

    def inspect
      reference = '0x0%x' % (self.object_id << 1)
      "#<#{self.class}:#{reference} " \
      "@channel=#{self.channel.inspect} " \
      "@name=#{self.name.inspect} " \
      "@params=#{self.params.inspect} " \
      "@publisher=#{self.publisher.inspect} " \
      "@published_at=#{self.published_at.inspect}>"
    end

    def ==(other)
      if other.kind_of?(self.class)
        self.payload_type == other.payload_type &&
        self.channel      == other.channel      &&
        self.name         == other.name         &&
        self.params       == other.params       &&
        self.publisher    == other.publisher    &&
        self.published_at == other.published_at
      else
        super
      end
    end

    private

    def validate!(channel, name, params)
      problem = if channel.to_s.empty?
        "The event doesn't have a channel."
      elsif name.to_s.empty?
        "The event doesn't have a name."
      elsif !params.kind_of?(::Hash)
        "The event's params are not valid."
      end
      raise(InvalidError, problem) if problem
    end

    module RouteName
      def self.new(event_channel, event_name)
        "#{event_channel}:#{event_name}"
      end
    end

    module SubscribersRedisKey
      def self.new(route_name)
        "events:#{route_name}:subscribers"
      end
    end

    InvalidError = Class.new(ArgumentError)

  end

end
