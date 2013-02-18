require 'system_timer'

module Qs

  TimeoutError = Class.new(RuntimeError)

  class Runner
    attr_reader :handler_class, :job, :handler

    # TODO: after initial beta...
    # TODO: Qs::Runner.run(MyJobHandler, {'some' => 'args'})
    # TODO: (in handler) run_job_handler(*args) that calls above
    # TODO: (in handler) run_event_handler that's similar to above

    def initialize(handler_class, job)
      @handler_class, @job = handler_class, job
      @handler = @handler_class.new(@job.handler_args, @job)
    end

    def run
      timeout_after(@handler.timeout, 'init') { @handler.init }
      timeout_after(@handler.timeout, 'run')  { @handler.run  }
    end

    module TimeoutMethods

      private

      def timeout_after(timeout, action, &block)
        begin
          SystemTimer.timeout(timeout, Qs::TimeoutError, &block)
        rescue Qs::TimeoutError => err
          err.message.replace "`#{@handler_class}` timed out"\
                              " during `#{action}` (#{timeout}s)."
          raise(err)
        end
      end

    end
    include TimeoutMethods

  end

end
