require 'dat-worker-pool/worker'
require 'qs/queue'

module Qs

  class ErrorHandler

    # these are standard error classes that we rescue and run through any
    # configured error procs; use the same standard error classes that
    # dat-worker-pool rescues
    STANDARD_ERROR_CLASSES = DatWorkerPool::Worker::STANDARD_ERROR_CLASSES

    attr_reader :exception, :context, :error_procs

    def initialize(exception, context_hash)
      @exception   = exception
      @context     = ErrorContext.new(context_hash)
      @error_procs = context_hash[:daemon_data].error_procs.reverse
    end

    # The exception that we are handling can change in the case that the
    # configured error proc raises an exception. If this occurs, the new
    # exception will be passed to subsequent error procs. This is designed to
    # avoid "hidden" errors, this way the daemon will log based on the last
    # exception that occurred.
    def run
      @error_procs.each do |error_proc|
        begin
          error_proc.call(@exception, @context)
        rescue *STANDARD_ERROR_CLASSES => proc_exception
          @exception = proc_exception
        end
      end
    end

  end

  class ErrorContext
    attr_reader :daemon_data
    attr_reader :queue_name, :encoded_payload
    attr_reader :message, :handler_class

    def initialize(args)
      @daemon_data     = args.fetch(:daemon_data)
      @queue_name      = get_queue_name(args.fetch(:queue_redis_key))
      @encoded_payload = args.fetch(:encoded_payload)
      @message         = args.fetch(:message)
      @handler_class   = args.fetch(:handler_class)
    end

    def ==(other)
      if other.kind_of?(self.class)
        self.daemon_data     == other.daemon_data &&
        self.queue_name      == other.queue_name &&
        self.encoded_payload == other.encoded_payload &&
        self.message         == other.message &&
        self.handler_class   == other.handler_class
      else
        super
      end
    end

    private

    def get_queue_name(redis_key)
      Queue::RedisKey.parse_name(redis_key.to_s)
    end

  end

end
