module Qs

  class Job

    attr_reader :queue_class, :handler_class, :handler_args

    def initialize(*args)
      @handler_args, @handler_class, @queue_class = [
        args.last.kind_of?(::Hash) ? args.pop : {},
        (args.pop || '').to_s,
        (args.pop || '').to_s
      ]
    end

    def ==(other_job)
      self.queue_class   == other_job.queue_class   &&
      self.handler_class == other_job.handler_class &&
      self.handler_args  == other_job.handler_args
    end

  end

end
