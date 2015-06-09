require 'qs'
require 'qs/dispatch_job'
require 'qs/job_handler'

module Qs

  module DispatchJobHandler

    def self.included(klass)
      klass.class_eval do
        include Qs::JobHandler
        include InstanceMethods
      end
    end

    module InstanceMethods

      attr_reader :event, :subscribed_queue_names

      def init!
        @event = Qs::DispatchJob.event(job)
        @subscribed_queue_names = Qs.event_subscribers(@event)
        @qs_failed_dispatches = []
      end

      def run!
        logger.info "Dispatching #{self.event.route_name}"
        logger.info "  params:       #{self.event.params.inspect}"
        logger.info "  publisher:    #{self.event.publisher}"
        logger.info "  published at: #{self.event.published_at}"
        logger.info "Found #{self.subscribed_queue_names.size} subscribed queue(s):"
        self.subscribed_queue_names.each do |queue_name|
          qs_dispatch(queue_name, self.event)
        end
        qs_handle_errors(self.event, @qs_failed_dispatches)
      end

      private

      def qs_dispatch(queue_name, event)
        Qs.push(queue_name, Qs::Payload.event_hash(event))
        logger.info "  => #{queue_name}"
      rescue StandardError => exception
        logger.info "  => #{queue_name} (failed)"
        @qs_failed_dispatches << FailedDispatch.new(queue_name, exception)
      end

      def qs_handle_errors(event, failed_dispatches)
        return if failed_dispatches.empty?
        logger.info "Failed to dispatch the event to " \
                    "#{failed_dispatches.size} subscribed queues"
        descriptions = failed_dispatches.map do |fail|
          exception_desc = "#{fail.exception.class}: #{fail.exception.message}"
          logger.info "#{fail.queue_name}"
          logger.info "  #{exception_desc}"
          logger.info "  #{fail.exception.backtrace.first}"
          "#{fail.queue_name} - #{exception_desc}"
        end
        message = "#{event.route_name} event wasn't dispatched to:\n" \
                  "  #{descriptions.join("\n  ")}"
        raise DispatchError.new(message, failed_dispatches)
      end

    end

    FailedDispatch = Struct.new(:queue_name, :exception)

    class DispatchError < RuntimeError
      attr_reader :failed_dispatches

      def initialize(message, failed_dispatches)
        super message
        @failed_dispatches = failed_dispatches
      end
    end

  end

end
