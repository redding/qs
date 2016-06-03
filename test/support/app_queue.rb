require 'qs'

AppQueue = Qs::Queue.new do
  name 'qs-app-main'

  job_handler_ns 'AppHandlers'

  job 'basic',   'Basic'
  job 'error',   'Error'
  job 'timeout', 'Timeout'
  job 'slow',    'Slow'

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

    timeout 0.2

    def run!
      sleep 2
    end
  end

  class Slow
    include Qs::JobHandler

    def run!
      sleep 5
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

    timeout 0.2

    def run!
      sleep 2
    end
  end

  class SlowEvent
    include Qs::EventHandler

    def run!
      sleep 5
      Qs.redis.with{ |c| c.set('qs-app:slow:event', 'finished') }
    end
  end

end
