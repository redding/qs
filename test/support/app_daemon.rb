require 'qs'

LOGGER = Logger.new(ROOT_PATH.join('log/app_daemon.log').to_s)
LOGGER.datetime_format = "" # turn off the datetime in the logs

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

class AppDaemon
  include Qs::Daemon

  name 'qs-app'

  logger LOGGER
  verbose_logging true

  queue AppQueue

  error do |exception, context|
    return unless (message = context.message)
    payload_type = message.payload_type
    route_name   = message.route_name
    case(route_name)
    when 'error', 'timeout', 'qs-app:error', 'qs-app:timeout'
      error = "#{exception.class}: #{exception.message}"
      Qs.redis.with{ |c| c.set("qs-app:last_#{payload_type}_error", error) }
    when 'slow', 'qs-app:slow'
      error = exception.class.to_s
      Qs.redis.with{ |c| c.set("qs-app:last_#{payload_type}_error", error) }
    end
  end

end

DISPATCH_LOGGER = Logger.new(ROOT_PATH.join('log/app_dispatcher_daemon.log').to_s)
DISPATCH_LOGGER.datetime_format = "" # turn off the datetime in the logs

class DispatcherDaemon
  include Qs::Daemon

  name 'qs-app-dispatcher'

  logger DISPATCH_LOGGER
  verbose_logging true

  # we build a "custom" dispatcher because we can't rely on Qs being initialized
  # when this is required
  queue Qs::DispatcherQueue.new({
    :queue_class            => Qs.config.dispatcher_queue_class,
    :queue_name             => 'qs-app-dispatcher',
    :job_name               => Qs.config.dispatcher.job_name,
    :job_handler_class_name => Qs.config.dispatcher.job_handler_class_name
  })
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
