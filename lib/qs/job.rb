module Qs

  class Job

    # TODO: move to an engine handler
    # def self.from_queue(queue_class, *queue_args)
    #   data = QueueJobData.new(*queue_args)
    #   Job.new(queue_class, data.handler_class_string, data.handler_args_hash)
    # end

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
