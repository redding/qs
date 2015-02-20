require 'qs'
require 'json'

BenchQueue = Qs::Queue.new do
  name 'bench'

  job 'multiply', 'BenchDaemon::Multiply'
end
