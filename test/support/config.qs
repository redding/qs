require 'test/support/app_daemon'

if !defined?(TestConstant)
  TestConstant = Class.new
end

run AppDaemon.new
