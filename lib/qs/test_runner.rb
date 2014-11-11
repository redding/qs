require 'qs/job_handler'
require 'qs/runner'

module Qs

  InvalidJobHandlerError = Class.new(StandardError)

  class TestRunner < Runner

    def initialize(handler_class, args = nil)
      if !handler_class.include?(Qs::JobHandler)
        raise InvalidJobHandlerError, "#{handler_class.inspect} is not a"\
                                      " Qs::JobHandler"
      end
      args = (args || {}).dup
      super(handler_class, {
        :job    => args.delete(:job),
        :params => args.delete(:params),
        :logger => args.delete(:logger)
      })
      args.each{ |key, value| self.handler.send("#{key}=", value) }

      self.handler.init
    end

    def run
      self.handler.run
    end

  end

end
