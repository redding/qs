require 'assert'
require 'qs/daemon_data'

require 'qs/queue'
require 'qs/route'

class Qs::DaemonData

  class UnitTests < Assert::Context
    desc "Qs::DaemonData"
    setup do
      @name = Factory.string
      @pid_file = Factory.file_path
      @min_workers = Factory.integer
      @max_workers = Factory.integer
      @logger = Factory.string
      @verbose_logging = Factory.boolean
      @shutdown_timeout = Factory.integer
      @error_procs = [ proc{ Factory.string } ]
      @queue_redis_keys = (0..Factory.integer(3)).map{ Factory.string }
      @routes = (0..Factory.integer(3)).map do
        Qs::Route.new(Factory.string, TestHandler.to_s).tap(&:validate!)
      end

      @daemon_data = Qs::DaemonData.new({
        :name => @name,
        :pid_file => @pid_file,
        :min_workers => @min_workers,
        :max_workers => @max_workers,
        :logger => @logger,
        :verbose_logging => @verbose_logging,
        :shutdown_timeout => @shutdown_timeout,
        :error_procs => @error_procs,
        :queue_redis_keys => @queue_redis_keys,
        :routes => @routes
      })
    end
    subject{ @daemon_data }

    should have_readers :name
    should have_readers :pid_file
    should have_readers :min_workers, :max_workers
    should have_readers :logger, :verbose_logging
    should have_readers :shutdown_timeout
    should have_readers :error_procs
    should have_readers :queue_redis_keys, :routes
    should have_imeths :route_for

    should "know its attributes" do
      assert_equal @name, subject.name
      assert_equal @pid_file, subject.pid_file
      assert_equal @min_workers, subject.min_workers
      assert_equal @max_workers, subject.max_workers
      assert_equal @logger, subject.logger
      assert_equal @verbose_logging, subject.verbose_logging
      assert_equal @shutdown_timeout, subject.shutdown_timeout
      assert_equal @error_procs, subject.error_procs
      assert_equal @queue_redis_keys, subject.queue_redis_keys
    end

    should "build a routes lookup hash" do
      expected = @routes.inject({}){ |h, r| h.merge(r.name => r) }
      assert_equal expected, subject.routes
    end

    should "allow looking up a route using `route_for`" do
      expected = @routes.choice
      route = subject.route_for(expected.name)
      assert_equal expected, route
    end

    should "raise a not found error using `route_for` with an invalid name" do
      assert_raises(Qs::NotFoundError) do
        subject.route_for(Factory.string)
      end
    end

    should "default its attributes when they aren't provided" do
      daemon_data = Qs::DaemonData.new
      assert_nil daemon_data.name
      assert_nil daemon_data.pid_file
      assert_nil daemon_data.min_workers
      assert_nil daemon_data.max_workers
      assert_nil daemon_data.logger
      assert_false daemon_data.verbose_logging
      assert_nil daemon_data.shutdown_timeout
      assert_equal [], daemon_data.error_procs
      assert_equal [], daemon_data.queue_redis_keys
      assert_equal({}, daemon_data.routes)
    end

  end

  TestHandler = Class.new

end
