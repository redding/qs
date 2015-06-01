require 'qs/message_handler'

module Qs

  module EventHandler

    def self.included(klass)
      klass.class_eval do
        include Qs::MessageHandler
        include InstanceMethods
      end
    end

    module InstanceMethods

      def inspect
        reference = '0x0%x' % (self.object_id << 1)
        "#<#{self.class}:#{reference} @event=#{event.inspect}>"
      end

      private

      # Helpers

      def event;              @qs_runner.message; end
      def event_channel;      event.channel;      end
      def event_name;         event.name;         end
      def event_published_at; event.published_at; end

    end

  end

end
