module Qs

  class ErrorHandler

    attr_reader :exception, :daemon_data, :job
    attr_reader :error_procs

    def initialize(exception, daemon_data, job = nil)
      @exception, @daemon_data, @job = exception, daemon_data, job
      @error_procs = @daemon_data.error_procs.reverse
    end

    # The exception that we are handling can change in the case that the
    # configured error proc raises an exception. If this occurs, the new
    # exception will be passed to subsequent error procs. This is designed to
    # avoid "hidden" errors, this way the daemon will log based on the last
    # exception that occurred.

    def run
      @error_procs.each do |error_proc|
        begin
          error_proc.call(@exception, @daemon_data, @job)
        rescue StandardError => proc_exception
          @exception = proc_exception
        end
      end
    end

  end

end
