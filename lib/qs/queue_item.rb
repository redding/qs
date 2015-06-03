module Qs

  class QueueItem

    attr_reader :queue_redis_key, :encoded_payload
    attr_accessor :started, :finished
    attr_accessor :message, :handler_class
    attr_accessor :exception, :time_taken

    def initialize(queue_redis_key, encoded_payload)
      @queue_redis_key = queue_redis_key
      @encoded_payload = encoded_payload
      @started         = false
      @finished        = false

      @message       = nil
      @handler_class = nil
      @exception     = nil
      @time_taken    = nil
    end

    def ==(other)
      if other.kind_of?(self.class)
        self.queue_redis_key == other.queue_redis_key &&
        self.encoded_payload == other.encoded_payload
      else
        super
      end
    end

  end

end
