require 'qs/queue'

module Qs

  class ErrorHandler

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
        rescue StandardError => proc_exception
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
      @daemon_data     = args[:daemon_data]
      @queue_name      = Queue::RedisKey.parse_name(args[:queue_redis_key].to_s)
      @encoded_payload = args[:encoded_payload]
      @message         = args[:message]
      @handler_class   = args[:handler_class]
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
  end

end
