# this file is automatically required when you run `assert`
# put any test helpers here

# add the root dir to the load path
$LOAD_PATH.unshift(File.expand_path("../..", __FILE__))

require 'test/support/job_handlers'
require 'test/support/event_handlers'
require 'test/support/queues'

require 'qs'
require 'qs/redis_connection'

Qs.configure do |c|
  c.redis.redis_ns 'qs-test'
  c.redis.size     1
end
Qs.init

class Assert::Context

  # remove all keys added during tests (cleanup after the tests)
  teardown_once do
    Qs.redis do |conn|
      conn.keys.each{ |key| conn.del(key) }
    end
  end

end
