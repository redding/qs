require 'qs/event'
require 'qs/job_handler'

module Qs

  module EventHandler

    def self.included(klass)
      klass.class_eval do
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

      def event;  @qs_event;        end
      def params; @qs_event.params; end

    end

  end

end
