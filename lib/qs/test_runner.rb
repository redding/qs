require 'qs'
require 'qs/event_handler'
require 'qs/job_handler'
require 'qs/payload'
require 'qs/runner'

module Qs

  class TestRunner < Runner

    def initialize(handler_class, args = nil)
      a = (args || {}).dup
      super(handler_class, {
        :logger  => a.delete(:logger),
        :message => a.delete(:message),
        :params  => normalize_params(a.delete(:params) || {})
      })
      a.each{ |key, value| self.handler.send("#{key}=", value) }

      @halted = false
      catch(:halt){ self.handler.qs_init }
    end

    def halted?; @halted; end

    def run
      catch(:halt){ self.handler.qs_run } if !self.halted?
    end

    # helpers

    def halt
      @halted = true
      super
    end

    private

    # stringify and encode/decode to ensure params are valid and are
    # in the format they would normally be when a live handler is built and run.
    def normalize_params(params)
      params = Qs::Payload::StringifyParams.new(params)
      Qs.decode(Qs.encode(params))
    end

  end

  class JobTestRunner < TestRunner

    def initialize(handler_class, args = nil)
      if !handler_class.include?(Qs::JobHandler)
        raise InvalidJobHandlerError, "#{handler_class.inspect} is not a " \
                                      "Qs::JobHandler"
      end

      a = (args || {}).dup
      a[:message] = a.delete(:job) if a.key?(:job)
      super(handler_class, a)
    end

  end

  class EventTestRunner < TestRunner

    def initialize(handler_class, args = nil)
      if !handler_class.include?(Qs::EventHandler)
        raise InvalidEventHandlerError, "#{handler_class.inspect} is not a " \
                                        "Qs::EventHandler"
      end

      a = (args || {}).dup
      a[:message] = a.delete(:event) if a.key?(:event)
      super(handler_class, a)
    end

  end

  InvalidJobHandlerError   = Class.new(StandardError)
  InvalidEventHandlerError = Class.new(StandardError)

end
