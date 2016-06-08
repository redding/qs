require 'qs'

AppQueue = Qs::Queue.new do
  name 'qs-app-main'

  job_handler_ns 'AppHandlers'

  job 'basic',   'Basic'
  job 'basic1',  'Basic'
  job 'error',   'Error'
  job 'timeout', 'Timeout'
  job 'slow',    'Slow'
  job 'slow1',   'Slow'
  job 'slow2',   'Slow'

  event_handler_ns 'AppHandlers'

  event 'qs-app', 'basic',   'BasicEvent'
  event 'qs-app', 'error',   'ErrorEvent'
  event 'qs-app', 'timeout', 'TimeoutEvent'
  event 'qs-app', 'slow',    'SlowEvent'
end

module AppHandlers

  class Basic
    include Qs::JobHandler

    def run!
      Qs.redis.with{ |c| c.set("qs-app:#{params['key']}", params['value']) }
    end
  end

  class Error
    include Qs::JobHandler

    def run!
      raise params['error_message']
    end
  end

  class Timeout
    include Qs::JobHandler

    TIMEOUT_TIME = 0.1

    timeout TIMEOUT_TIME

    def run!
      sleep 2*TIMEOUT_TIME
    end
  end

  class Slow
    include Qs::JobHandler

    SLOW_TIME = 1

    def run!
      sleep SLOW_TIME
      Qs.redis.with{ |c| c.set('qs-app:slow', 'finished') }
    end
  end

  class BasicEvent
    include Qs::EventHandler

    def run!
      Qs.redis.with{ |c| c.set("qs-app:#{params['key']}", params['value']) }
    end
  end

  class ErrorEvent
    include Qs::EventHandler

    def run!
      raise params['error_message']
    end
  end

  class TimeoutEvent
    include Qs::EventHandler

    TIMEOUT_TIME = 0.1

    timeout TIMEOUT_TIME

    def run!
      sleep 2*TIMEOUT_TIME
    end
  end

  class SlowEvent
    include Qs::EventHandler

    SLOW_TIME = 1

    def run!
      sleep SLOW_TIME
      Qs.redis.with{ |c| c.set('qs-app:slow:event', 'finished') }
    end
  end

end
