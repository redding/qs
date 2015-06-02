require 'qs'
require 'qs/event'
require 'qs/event_handler'
require 'qs/job_handler'
require 'qs/payload'
require 'qs/runner'

module Qs

  class TestRunner < Runner

    def initialize(handler_class, args = nil)
      args = (args || {}).dup
      super(handler_class, {
        :message => args.delete(:message),
        :params  => normalize_params(args.delete(:params) || {}),
        :logger  => args.delete(:logger)
      })
      args.each{ |key, value| self.handler.send("#{key}=", value) }

      self.handler.init
    end

    def run
      self.handler.run
    end

    private

    # Stringify and encode/decode to ensure params are valid and are
    # in the format they would normally be when a handler is built and run.
    def normalize_params(params)
      params = Qs::Payload::StringifyParams.new(params)
      Qs.decode(Qs.encode(params))
    end

  end

  class JobTestRunner < TestRunner

    def initialize(handler_class, args = nil)
      if !handler_class.include?(Qs::JobHandler)
        raise InvalidJobHandlerError, "#{handler_class.inspect} is not a"\
                                      " Qs::JobHandler"
      end

      args = (args || {}).dup
      args[:message] = args.delete(:job) if args.key?(:job)
      super(handler_class, args)
    end

  end

  class EventTestRunner < TestRunner

    def initialize(handler_class, args = nil)
      if !handler_class.include?(Qs::EventHandler)
        raise InvalidEventHandlerError, "#{handler_class.inspect} is not a"\
                                      " Qs::EventHandler"
      end

      args = (args || {}).dup
      # TODO - change to this once events are a kind of message
      # args[:message] = args.delete(:event) if args.key?(:event)
      channel      = args.delete(:event_channel) || 'a-channel'
      name         = args.delete(:event_name)    || 'a-name'
      params       = args.delete(:params) || args.delete(:event_params) || {}
      published_at = args.delete(:event_published_at)
      args[:message] = Event.build(channel, name, params, {
        :published_at => published_at
      }).job
      args[:params] = args[:message].params
      super(handler_class, args)
    end

  end

  InvalidJobHandlerError   = Class.new(StandardError)
  InvalidEventHandlerError = Class.new(StandardError)

end
