require 'assert'
require 'qs/redis_connection'

module Qs::RedisConnection

  class UnitTests < Assert::Context
    desc "Qs::RedisConnection"
    setup do
      @hella_redis_conn = Factory.string
      Assert.stub(HellaRedis::RedisConnection, :new) do |config|
        @config = config
        @hella_redis_conn
      end

      @options = {
        :url      => Factory.url,
        :redis_ns => Factory.string,
        :driver   => Factory.string,
        :timeout  => Factory.integer,
        :size     => Factory.integer
      }
      @redis_connection = Qs::RedisConnection.new(@options)
    end
    subject{ @redis_connection }

    should "build a hella redis connection" do
      assert_instance_of Config, @config
      assert_equal @options[:url], @config.url
      assert_equal @options[:redis_ns], @config.redis_ns
      assert_equal @options[:driver], @config.driver
      assert_equal @options[:timeout], @config.timeout
      assert_equal @options[:size], @config.size
      assert_equal @hella_redis_conn, subject
    end

  end

end
