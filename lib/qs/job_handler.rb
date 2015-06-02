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

      def job;            @qs_runner.job; end
      def job_name;       job.name;       end
      def job_created_at; job.created_at; end

    end

  end

end
