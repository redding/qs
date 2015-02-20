require 'benchmark'
require 'qs'
require 'qs/error_handler'
require 'qs/job'
require 'qs/logger'

module Qs

  class PayloadHandler

    ProcessedPayload = Struct.new(:job, :handler_class, :exception, :time_taken)

    attr_reader :daemon_data, :serialized_payload, :logger

    def initialize(daemon_data, serialized_payload)
      @daemon_data = daemon_data
      @serialized_payload = serialized_payload
      @logger = Qs::Logger.new(
        @daemon_data.logger,
        @daemon_data.verbose_logging
      )
    end

    def run
      processed_payload = nil
      log_received
      benchmark = Benchmark.measure do
        processed_payload = run!
      end
      processed_payload.time_taken = RoundedTime.new(benchmark.real)
      log_complete(processed_payload)
      raise_if_debugging!(processed_payload.exception)
      processed_payload
    end

    private

    def run!
      processed_payload = ProcessedPayload.new
      begin
        payload = Qs.deserialize(@serialized_payload)
        job = Qs::Job.parse(payload)
        log_job(job)
        processed_payload.job = job

        route = @daemon_data.route_for(job.name)
        log_handler_class(route.handler_class)
        processed_payload.handler_class = route.handler_class

        route.run(job, @daemon_data)
      rescue StandardError => exception
        handle_exception(exception, @daemon_data, processed_payload)
      end
      processed_payload
    end

    def handle_exception(exception, daemon_data, processed_payload)
      error_handler = Qs::ErrorHandler.new(
        exception,
        daemon_data,
        processed_payload.job
      ).tap(&:run)
      processed_payload.exception = error_handler.exception
      log_exception(processed_payload.exception)
      processed_payload
    end

    def raise_if_debugging!(exception)
      raise exception if exception && ENV['QS_DEBUG']
    end

    def log_received
      log_verbose "===== Running job ====="
    end

    def log_job(job)
      log_verbose "  Job:     #{job.name.inspect}"
      log_verbose "  Params:  #{job.params.inspect}"
    end

    def log_handler_class(handler_class)
      log_verbose "  Handler: #{handler_class}"
    end

    def log_complete(processed_payload)
      log_verbose "===== Completed in #{processed_payload.time_taken}ms ====="
      summary_line_args = {
        'time'    => processed_payload.time_taken,
        'handler' => processed_payload.handler_class
      }
      if (job = processed_payload.job)
        summary_line_args['job']    = job.name
        summary_line_args['params'] = job.params
      end
      if (exception = processed_payload.exception)
        summary_line_args['error'] = "#{exception.inspect}"
      end
      log_summary SummaryLine.new(summary_line_args)
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

    module RoundedTime
      ROUND_PRECISION = 2
      ROUND_MODIFIER = 10 ** ROUND_PRECISION
      def self.new(time_in_seconds)
        (time_in_seconds * 1000 * ROUND_MODIFIER).to_i / ROUND_MODIFIER.to_f
      end
    end

    module SummaryLine
      def self.new(line_attrs)
        attr_keys = %w{time handler job params error}
        attr_keys.map{ |k| "#{k}=#{line_attrs[k].inspect}" }.join(' ')
      end
    end

  end

end
