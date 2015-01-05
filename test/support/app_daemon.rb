require 'qs'

AppQueue = Qs::Queue.new do
  name 'app_main'
end

class AppDaemon
  include Qs::Daemon

  name 'app'
  queue AppQueue
end
