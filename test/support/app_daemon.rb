require 'qs'

AppQueue = Qs::Queue.new do
  name 'app_main'

  job_handler_ns 'AppHandlers'

  job 'basic',   'Basic'
  job 'error',   'Error'
  job 'timeout', 'Timeout'
  job 'slow',    'Slow'
end

class AppDaemon
  include Qs::Daemon

  name 'app'

  logger Logger.new(ROOT_PATH.join('log/app_daemon.log').to_s)
  verbose_logging true

  queue AppQueue

  error do |exception, context|
    job_name = context.job.name if context.job
    case(job_name)
    when 'error', 'timeout'
      message = "#{exception.class}: #{exception.message}"
      Qs.redis.with{ |c| c.set('last_error', message) }
    when 'slow'
      Qs.redis.with{ |c| c.set('last_error', exception.class.to_s) }
    end
  end

end

module AppHandlers

  class Basic
    include Qs::JobHandler

    def run!
      Qs.redis.with{ |c| c.set(params['key'], params['value']) }
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
      Qs.redis.with{ |c| c.set('slow', 'finished') }
    end
  end

end
