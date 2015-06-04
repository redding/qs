require 'qs'
require 'json'

ROOT_PATH = Pathname.new(File.expand_path('../..', __FILE__))

LOGGER = if ENV['BENCH_REPORT']
  Logger.new(ROOT_PATH.join(ENV['LOG_NAME']).to_s)
else
  Logger.new(STDOUT)
end
LOGGER.datetime_format = "" # turn off the datetime in the logs

PROGRESS_IO = if ENV['BENCH_PROGRESS_IO']
  ::IO.for_fd(ENV['BENCH_PROGRESS_IO'].to_i)
else
  File.open('/dev/null', 'w')
end

Qs.config.dispatcher.queue_name = 'bench-dispatcher'
Qs.config.event_publisher = 'Bench Script'
Qs.init

BenchQueue = Qs::Queue.new do
  name 'bench'

  job 'multiply', 'BenchHandlers::Multiply'

  event 'something', 'happened', 'BenchHandlers::SomethingHappened'

end
BenchQueue.sync_subscriptions

module BenchHandlers

  class Multiply
    include Qs::JobHandler

    after{ PROGRESS_IO.write_nonblock('.') }

    def run!
      'a' * params['size']
    end
  end

  class SomethingHappened
    include Qs::EventHandler

    after{ PROGRESS_IO.write_nonblock('.') }

    def run!
      'a' * params['size']
    end
  end

end
