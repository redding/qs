require 'benchmark'
require 'dat-worker-pool'
require 'qs/error_handler'
require 'qs/event'
require 'qs/job'
require 'qs/logger'
require 'qs/payload'

module Qs

  class PayloadHandler

    attr_reader :daemon_data, :queue_item, :logger

    def initialize(daemon_data, queue_item)
      @daemon_data = daemon_data
      @queue_item  = queue_item
      @logger = Qs::Logger.new(
        @daemon_data.logger,
        @daemon_data.verbose_logging
      )
    end

    def run
      log_received
      benchmark = Benchmark.measure{ run!(@daemon_data, @queue_item) }
      @queue_item.time_taken = RoundedTime.new(benchmark.real)
      log_complete(@queue_item)
      raise_if_debugging!(@queue_item.exception)
    end

    private

    def run!(daemon_data, queue_item)
      queue_item.started = true

      message = Qs::Payload.deserialize(queue_item.encoded_payload)
      log_message(message)
      queue_item.message = message

      route = daemon_data.route_for(message.route_id)
      log_handler_class(route.handler_class)
      queue_item.handler_class = route.handler_class

      route.run(message, daemon_data)
      queue_item.finished = true
    rescue DatWorkerPool::ShutdownError => exception
      if queue_item.started
        error = ShutdownError.new(exception.message)
        error.set_backtrace(exception.backtrace)
        handle_exception(error, daemon_data, queue_item)
      end
      raise exception
    rescue StandardError => exception
      handle_exception(exception, daemon_data, queue_item)
    end

    def handle_exception(exception, daemon_data, queue_item)
      error_handler = Qs::ErrorHandler.new(exception, {
        :daemon_data     => daemon_data,
        :queue_redis_key => queue_item.queue_redis_key,
        :encoded_payload => queue_item.encoded_payload,
        :message         => queue_item.message,
        :handler_class   => queue_item.handler_class
      }).tap(&:run)
      queue_item.exception = error_handler.exception
      log_exception(queue_item.exception)
    end

    def raise_if_debugging!(exception)
      raise exception if exception && ENV['QS_DEBUG']
    end

    def log_received
      log_verbose "===== Received message ====="
    end

    def log_message(message)
      self.send("log_#{Qs::Payload.type_method_name(message.payload_type)}", message)
      log_verbose "  Params:    #{message.params.inspect}"
    end

    def log_job(job)
      log_verbose "  Job:       #{job.route_name.inspect}"
    end

    def log_event(event)
      log_verbose "  Event:     #{event.route_name.inspect}"
      log_verbose "  Publisher: #{event.publisher.inspect}"
    end

    def log_handler_class(handler_class)
      log_verbose "  Handler:   #{handler_class}"
    end

    def log_complete(queue_item)
      log_verbose "===== Completed in #{queue_item.time_taken}ms ====="
      log_summary build_summary_line(queue_item)
    end

    def log_exception(exception)
      backtrace = exception.backtrace.join("\n")
      message = "#{exception.class}: #{exception.message}\n#{backtrace}"
      log_verbose(message, :error)
    end

    def log_verbose(message, level = :info)
      self.logger.verbose.send(level, "[Qs] #{message}")
    end

    def log_summary(message, level = :info)
      self.logger.summary.send(level, "[Qs] #{message}")
    end

    def build_summary_line(queue_item)
      summary_line_args = {
        'time'    => queue_item.time_taken,
        'handler' => queue_item.handler_class
      }
      if (exception = queue_item.exception)
        summary_line_args['error'] = "#{exception.class}: #{exception.message}"
      end
      if (message = queue_item.message)
        summary_line_args['params'] = message.params
        self.send(
          "#{Qs::Payload.type_method_name(message.payload_type)}_summary_line",
          message,
          summary_line_args
        )
      else
        UnknownSummaryLine.new(summary_line_args)
      end
    end

    def job_summary_line(job, summary_line_args)
      JobSummaryLine.new(job, summary_line_args)
    end

    def event_summary_line(event, summary_line_args)
      EventSummaryLine.new(event, summary_line_args)
    end

    module SummaryLine
      def self.new(keys, line_attrs)
        keys.map{ |k| "#{k}=#{line_attrs[k].inspect}" }.join(' ')
      end
    end

    module UnknownSummaryLine
      ORDERED_KEYS = %w(time handler error).freeze

      def self.new(line_attrs)
        SummaryLine.new(ORDERED_KEYS, line_attrs)
      end
    end

    module JobSummaryLine
      ORDERED_KEYS = %w(time handler job params error).freeze

      def self.new(job, line_attrs)
        SummaryLine.new(ORDERED_KEYS, line_attrs.merge('job' => job.route_name))
      end
    end

    module EventSummaryLine
      ORDERED_KEYS = %w(time handler event publisher params error).freeze

      def self.new(event, line_attrs)
        SummaryLine.new(ORDERED_KEYS, line_attrs.merge({
          'event'     => event.route_name,
          'publisher' => event.publisher
        }))
      end
    end

    module RoundedTime
      ROUND_PRECISION = 2
      ROUND_MODIFIER = 10 ** ROUND_PRECISION
      def self.new(time_in_seconds)
        (time_in_seconds * 1000 * ROUND_MODIFIER).to_i / ROUND_MODIFIER.to_f
      end
    end

  end

  ShutdownError = Class.new(DatWorkerPool::ShutdownError)

end
