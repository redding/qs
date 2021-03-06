require 'dat-worker-pool/worker'
require 'much-plugin'
require 'qs/client'
require 'qs/daemon'
require 'qs/daemon_data'
require 'qs/payload_handler'

module Qs

  module Worker
    include MuchPlugin

    plugin_included do
      include DatWorkerPool::Worker
      include InstanceMethods

      on_available{ params[:qs_worker_available].signal }

      on_error{ |e, wi| qs_handle_exception(e, wi) }

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

    module TestHelpers
      include MuchPlugin

      plugin_included do
        include DatWorkerPool::Worker::TestHelpers
        include InstanceMethods
      end

      module InstanceMethods

        def test_runner(worker_class, options = nil)
          options ||= {}
          options[:params] = {
            :qs_daemon_data      => Qs::DaemonData.new,
            :qs_client           => Qs::TestClient.new({}),
            :qs_worker_available => Qs::Daemon::WorkerAvailable.new,
            :qs_logger           => Qs::NullLogger.new
          }.merge(options[:params] || {})
          super(worker_class, options)
        end

      end

    end

  end

end
