require 'much-timeout'
require 'qs'
require 'qs/runner'

module Qs

  class QsRunner < Runner

    attr_reader :timeout

    def initialize(handler_class, args = nil)
      super(handler_class, args)
      @timeout = handler_class.timeout || Qs.config.timeout
    end

    def run
      MuchTimeout.optional_timeout(self.timeout, TimeoutInterrupt) do
        catch(:halt) do
          self.handler.qs_run_callback 'before'
          catch(:halt){ self.handler.qs_init; self.handler.qs_run }
          self.handler.qs_run_callback 'after'
        end
      end
    rescue TimeoutInterrupt => exception
      error = Qs::TimeoutError.new "#{handler_class} timed out (#{timeout}s)"
      error.set_backtrace(exception.backtrace)
      raise error
    end

    # this error should never be "swallowed", if it is caught be sure to re-raise
    # it so the workers will be able to honor their timeout setting.  otherwise
    # workers will never timeout.
    TimeoutInterrupt = Class.new(Interrupt)

  end

end
