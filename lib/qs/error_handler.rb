module Qs

  class ErrorHandler

    def initialize(error_procs, queue)
      @error_procs = [*error_procs].compact
      @queue       = queue
    end

    def run(exception, job = nil)
      # TODO
      raise NotImplementedError
    end

  end

end
