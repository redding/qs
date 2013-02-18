require 'qs/job_handler'

module Qs

  module EventHandler

    # The order of these includes is important. The `InstanceMethods` module
    # needs to `super` to the job handler initialize. To enforce this,
    # the job handler mixin must be included before the `InstanceMethods` module.

    def self.included(klass)
      klass.class_eval do
        include Qs::JobHandler
        include Qs::EventHandler::InstanceMethods
      end
    end

    module InstanceMethods
      attr_reader :published_event

      def initialize(args, enqueued_job)
        @published_event = Event.from_job(enqueued_job)
        super(@published_event.args, enqueued_job)
      end
    end

  end

end
