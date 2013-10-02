module Qs

  class Runner

    def self.run(handler_class, job, logger)
      self.new(handler_class, job, logger).run
    end

    def initialize(handler_class, job, logger = nil)
      # TODO
      @handler_class = handler_class
      @job           = job
      @logger        = logger
    end

  end

end
