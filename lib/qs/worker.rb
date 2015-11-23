require 'dat-worker-pool/worker'
require 'qs/payload_handler'

module Qs

  module Worker

    IVAR_NAME = "@qs_worker_mixin_included_already".freeze

    def self.included(klass)
      return if klass.instance_variable_get(IVAR_NAME)

      klass.class_eval do
        include DatWorkerPool::Worker
        include InstanceMethods

        on_available{ params[:qs_worker_available].signal }

        on_error{ |e, wi| qs_handle_exception(e, wi) }

      end

      klass.instance_variable_set(IVAR_NAME, true)
    end

    module InstanceMethods

      def work!(queue_item)
        Qs::PayloadHandler.new(params[:qs_daemon_data], queue_item).run
      end

      private

      # this only catches errors that happen outside of running the payload
      # handler, the only known use-case for this is dwps shutdown errors; if
      # there isn't a queue item (this can happen when an idle worker is being
      # forced to exit) then we don't need to do anything; if we never started
      # processing the queue item, its safe to requeue it, otherwise it happened
      # while it was being processed (by the payload handler) or after it was
      # processed, for these cases, either the payload handler caught the error
      # (while it was being processed) or we don't care because its been
      # processed and the worker is just finishing up
      def qs_handle_exception(exception, queue_item)
        return if queue_item.nil?
        if !queue_item.started
          qs_log "Worker error, requeueing message because it hasn't started", :error
          params[:qs_client].prepend(
            queue_item.queue_redis_key,
            queue_item.encoded_payload
          )
        else
          qs_log "Worker error after message was processed, ignoring", :error
        end
        qs_log "#{exception.class}: #{exception.message}", :error
        qs_log (exception.backtrace || []).join("\n"), :error
      end

      def qs_log(message, level = :info)
        params[:qs_logger].send(level, "[Qs-#{number}] #{message}")
      end

    end

  end

end
