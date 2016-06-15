$LOAD_PATH.push(File.expand_path('../..', __FILE__))
require 'qs'

ENV['LOG_NAME'] = 'log/bench_daemon.log'
require 'bench/setup'

class BenchDaemon
  include Qs::Daemon

  name     'bench'
  pid_file ROOT_PATH.join('tmp/bench_daemon.pid').to_s

  logger LOGGER
  verbose_logging false

  queue BenchQueue

  # if fails notify the bench report so it doesn't hang forever on IO.select
  error do |exception, context|
    PROGRESS_IO.write_nonblock('F')
  end

end

run BenchDaemon.new
