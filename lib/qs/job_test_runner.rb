require 'qs'
require 'qs/event'
require 'qs/event_handler'
require 'qs/job'
require 'qs/job_handler'
require 'qs/runner'

module Qs

  class JobTestRunner < Runner

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

  class EventTestRunner < JobTestRunner

    def initialize(handler_class, args = nil)
      if !handler_class.include?(Qs::EventHandler)
        raise InvalidEventHandlerError, "#{handler_class.inspect} is not a"\
                                      " Qs::EventHandler"
      end

      args         = (args || {}).dup
      channel      = args.delete(:event_channel) || 'a-channel'
      name         = args.delete(:event_name)    || 'a-name'
      params       = args.delete(:params) || args.delete(:event_params) || {}
      published_at = args.delete(:event_published_at)

      args[:job] = Event.build(channel, name, params, {
        :published_at => published_at
      }).job
      args[:params] = args[:job].params
      super(handler_class, args)
    end

  end

  InvalidJobHandlerError   = Class.new(StandardError)
  InvalidEventHandlerError = Class.new(StandardError)

end
