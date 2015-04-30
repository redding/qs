require 'qs'
require 'bench/queue'

ROOT_PATH = Pathname.new(File.expand_path('../..', __FILE__))

LOGGER = if ENV['BENCH_REPORT']
  Logger.new(ROOT_PATH.join('log/bench_daemon.log').to_s)
else
  Logger.new(STDOUT)
end
LOGGER.datetime_format = "" # turn off the datetime in the logs

PROGRESS_IO = if ENV['BENCH_PROGRESS_IO']
  ::IO.for_fd(ENV['BENCH_PROGRESS_IO'].to_i)
else
  File.open('/dev/null', 'w')
end

class BenchDaemon
  include Qs::Daemon

  name     'bench'
  pid_file ROOT_PATH.join('tmp/bench_daemon.pid').to_s

  logger LOGGER
  verbose_logging false

  queue BenchQueue

  # if jobs fail notify the bench report so it doesn't hang forever on IO.select
  error do |exception, daemon_data, job|
    PROGRESS_IO.write_nonblock('F')
  end

  class Multiply
    include Qs::JobHandler

    after{ PROGRESS_IO.write_nonblock('.') }

    def run!
      'a' * params['size']
    end
  end

end

run BenchDaemon.new
