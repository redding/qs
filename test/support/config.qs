require 'test/support/app_queue'

if !defined?(TestConstant)
  TestConstant = Class.new
end

class ConfigFileTestDaemon
  include Qs::Daemon

  name  'qs-config-file-test'
  queue AppQueue
end

run ConfigFileTestDaemon.new
