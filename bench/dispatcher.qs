$LOAD_PATH.push(File.expand_path('../..', __FILE__))
require 'qs'

ENV['LOG_NAME'] = 'log/bench_dispatcher_daemon.log'
require 'bench/setup'

class DispatcherDaemon
  include Qs::Daemon

  name     'bench-dispatcher'
  pid_file ROOT_PATH.join('tmp/bench_dispatcher_daemon.pid').to_s

  logger LOGGER
  verbose_logging false

  queue Qs.dispatcher_queue

  # if fails notify the bench report so it doesn't hang forever on IO.select
  error do |exception, context|
    PROGRESS_IO.write_nonblock('F')
  end

end

run DispatcherDaemon.new
