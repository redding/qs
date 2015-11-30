require 'much-plugin'
require 'qs/message_handler'

module Qs

  module EventHandler
    include MuchPlugin

    plugin_included do
      include Qs::MessageHandler
      include InstanceMethods
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

    module TestHelpers

      def self.included(klass)
        require 'qs/test_runner'
      end

      def test_runner(handler_class, args = nil)
        Qs::EventTestRunner.new(handler_class, args)
      end

      def test_handler(handler_class, args = nil)
        test_runner(handler_class, args).handler
      end

    end

  end

end
