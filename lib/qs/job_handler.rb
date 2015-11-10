require 'qs/message_handler'

module Qs

  module JobHandler

    def self.included(klass)
      klass.class_eval do
        include Qs::MessageHandler
        include InstanceMethods
      end
    end

    module InstanceMethods

      def inspect
        reference = '0x0%x' % (self.object_id << 1)
        "#<#{self.class}:#{reference} @job=#{job.inspect}>"
      end

      private

      # Helpers

      def job;            @qs_runner.message; end
      def job_name;       job.name;           end
      def job_created_at; job.created_at;     end

    end

    module TestHelpers

      def self.included(klass)
        require 'qs/test_runner'
      end

      def test_runner(handler_class, args = nil)
        Qs::JobTestRunner.new(handler_class, args)
      end

      def test_handler(handler_class, args = nil)
        test_runner(handler_class, args).handler
      end

    end

  end

end
