require 'qs/logger'

module Qs

  class Runner

    attr_reader :handler_class, :handler
    attr_reader :job, :params, :logger

    def initialize(handler_class, args = nil)
      @handler_class = handler_class

      a = args || {}
      @job    = a[:job]
      @params = a[:params] || {}
      @logger = a[:logger] || Qs::NullLogger.new

      @handler = @handler_class.new(self)
    end

    def run
      raise NotImplementedError
    end

  end

end
