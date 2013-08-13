require 'qs'

class MyDaemon
  include Qs::Daemon
end

run MyDaemon.new
