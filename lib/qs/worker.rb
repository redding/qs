require 'benchmark'

require 'qs/error_handler'
require 'qs/job'
require 'qs/runner'

module Qs

  class Worker

    def initialize(queue, error_procs = nil)
      @queue  = queue
      @logger = @queue.logger
      @error_handler = Qs::ErrorHandler.new(error_procs, @queue)
    end

    def run(encoded_job)
      log_received
      benchmark  = Benchmark.measure{ run!(encoded_job) }
      time_taken = RoundedTime.new(benchmark.real)
      log_complete(time_taken)
    end

    private

    def run!(encoded_job)
      job = Qs::Job.parse(encoded_job)
      log_job(job)

      handler_class = @queue.handler_class_for(job.type, job.name)
      log_handler_class(handler_class)

      Qs::Runner.new(handler_class, job, @logger).run
    rescue Exception => exception
      handle_exception(exception, job)
    end

    def handle_exception(exception, job)
      exception = @error_handler.run(exception, job)
      log_exception(exception)
      raise_if_debugging!(exception)
    end

    def raise_if_debugging!(exception)
      raise exception if exception && ENV['QS_DEBUG']
    end

    def log_received
      log "===== Received job ====="
    end

    def log_job(job)
      log "  Type:    #{job.type.inspect}"
      log "  Name:    #{job.name.inspect}"
      log "  Params:  #{job.params.inspect}"
    end

    def log_handler_class(handler_class)
      log "  Handler: #{handler_class}"
    end

    def log_complete(time_taken)
      log "===== Completed in #{time_taken}s ====="
    end

    def log_exception(exception)
      log("#{exception.class}: #{exception.message}", :error)
      log(exception.backtrace.join("\n"), :error)
    end

    def log(message, level = :info)
      @logger.send(level, "[Qs] #{message}")
    end

    module RoundedTime
      ROUND_PRECISION = 2
      ROUND_MODIFIER  = 10 ** ROUND_PRECISION
      def self.new(time_in_seconds)
        (time_in_seconds * ROUND_MODIFIER).to_i / ROUND_MODIFIER.to_f
      end
    end

  end

end
