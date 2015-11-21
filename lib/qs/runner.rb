require 'qs/logger'

module Qs

  class Runner

    attr_reader :handler_class, :handler
    attr_reader :logger, :message, :params

    def initialize(handler_class, args = nil)
      @handler_class = handler_class
      @handler = @handler_class.new(self)

      args ||= {}
      @logger  = args[:logger] || Qs::NullLogger.new
      @message = args[:message]
      @params  = args[:params] || {}
    end

    def run
      raise NotImplementedError
    end

  end

end
