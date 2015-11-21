require 'system_timer'
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
      OptionalTimeout.new(self.timeout) do
        self.handler.qs_run_callback 'before'
        self.handler.init
        self.handler.run
        self.handler.qs_run_callback 'after'
      end
    rescue TimeoutError => exception
      error = TimeoutError.new "#{handler_class} timed out (#{timeout}s)"
      error.set_backtrace(exception.backtrace)
      raise error
    end

    private

    module OptionalTimeout
      def self.new(timeout, &block)
        if !timeout.nil?
          SystemTimer.timeout_after(timeout, TimeoutError, &block)
        else
          block.call
        end
      end
    end

  end

  TimeoutError = Class.new(RuntimeError)

end
