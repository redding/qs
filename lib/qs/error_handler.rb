module Qs

  class ErrorHandler

    def initialize(queue, error_procs)
      @error_procs = [*error_procs].compact
      @queue       = queue
    end

    # If an error is raised from an error proc, it will be passed to the next
    # error proc. This is designed to avoid "hidden" errors happening, this way
    # the daemon will log based on the last exception that occurred.
    def run(exception, job = nil)
      @error_procs.each do |error_proc|
        begin
          error_proc.call(exception, @queue, job)
        rescue Exception => proc_exception
          exception = proc_exception
        end
      end
      exception
    end

  end

end
