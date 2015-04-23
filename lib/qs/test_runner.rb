require 'qs'
require 'qs/job'
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
        :params => normalize_params(args.delete(:params) || {}),
        :logger => args.delete(:logger)
      })
      args.each{ |key, value| self.handler.send("#{key}=", value) }

      self.handler.init
    end

    def run
      self.handler.run
    end

    private

    # Stringify and serialize/deserialize to ensure params are valid and are
    # in the format they would normally be when a handler is built and run.
    def normalize_params(params)
      params = Job::StringifyParams.new(params)
      Qs.deserialize(Qs.serialize(params))
    end

  end

end
