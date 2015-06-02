require 'qs/event'
require 'qs/message_handler'

module Qs

  module EventHandler

    def self.included(klass)
      klass.class_eval do
        include Qs::MessageHandler
        # TODO - remove once runners are updated to handle messages
        include Qs::JobHandler
        include InstanceMethods
      end
    end

    module InstanceMethods

      def initialize(*args)
        super
        @qs_event = Event.new(@qs_runner.job)
      end

      def inspect
        reference = '0x0%x' % (self.object_id << 1)
        "#<#{self.class}:#{reference} @event=#{event.inspect}>"
      end

      private

      # Helpers

      def event;              @qs_event;          end
      def event_channel;      event.channel;      end
      def event_name;         event.name;         end
      def event_published_at; event.published_at; end

      # TODO - remove once runners are updated to handle messages
      def params; @qs_event.params; end

    end

  end

end
