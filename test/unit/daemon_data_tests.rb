require 'assert'
require 'qs/daemon_data'

require 'qs/queue'
require 'qs/route'

class Qs::DaemonData

  class UnitTests < Assert::Context
    desc "Qs::DaemonData"
    setup do
      @current_env_process_label = ENV['QS_PROCESS_LABEL']
      ENV['QS_PROCESS_LABEL']    = Factory.string

      @current_env_debug = ENV['QS_DEBUG']
      ENV.delete('QS_DEBUG')

      @queues = Factory.integer(3).times.map do
        Qs::Queue.new{ name Factory.string }
      end

      @routes = Factory.integer(3).times.map do
        Qs::Route.new(Factory.string, TestHandler.to_s).tap(&:validate!)
      end

      @config_hash = {
        :name             => Factory.string,
        :pid_file         => Factory.file_path,
        :shutdown_timeout => Factory.integer,
        :worker_class     => Class.new,
        :worker_params    => { Factory.string => Factory.string },
        :num_workers      => Factory.integer,
        :error_procs      => Factory.integer(3).times.map{ proc{} },
        :logger           => Factory.string,
        :queues           => @queues,
        :verbose_logging  => Factory.boolean,
        :routes           => @routes
      }
      @daemon_data = Qs::DaemonData.new(@config_hash)
    end
    teardown do
      ENV['QS_DEBUG']         = @current_env_debug
      ENV['QS_PROCESS_LABEL'] = @current_env_process_label
    end
    subject{ @daemon_data }

    should have_readers :name, :pid_file, :shutdown_timeout
    should have_readers :worker_class, :worker_params, :num_workers
    should have_readers :error_procs, :logger, :queue_redis_keys
    should have_readers :verbose_logging
    should have_readers :debug, :dwp_logger, :routes, :process_label
    should have_imeths :route_for

    should "know its attrs" do
      h = @config_hash
      assert_equal h[:name],     subject.name
      assert_equal h[:pid_file], subject.pid_file

      assert_equal h[:shutdown_timeout], subject.shutdown_timeout

      assert_equal h[:worker_class],  subject.worker_class
      assert_equal h[:worker_params], subject.worker_params
      assert_equal h[:num_workers],   subject.num_workers
      assert_equal h[:error_procs],   subject.error_procs
      assert_equal h[:logger],        subject.logger

      exp = @queues.map(&:redis_key)
      assert_equal exp, subject.queue_redis_keys

      assert_equal h[:verbose_logging], subject.verbose_logging

      assert_false subject.debug
      assert_nil   subject.dwp_logger

      exp = @routes.inject({}){ |h, r| h.merge(r.id => r) }
      assert_equal exp, subject.routes
    end

    should "know its process label" do
      assert_equal ENV['QS_PROCESS_LABEL'], subject.process_label

      ENV['QS_PROCESS_LABEL'] = ""
      daemon_data = Qs::DaemonData.new(@config_hash)
      assert_equal @config_hash[:name], daemon_data.process_label

      ENV.delete('QS_PROCESS_LABEL')
      daemon_data = Qs::DaemonData.new(@config_hash)
      assert_equal @config_hash[:name], daemon_data.process_label
    end

    should "use the debug env var if set" do
      ENV['QS_DEBUG'] = Factory.string
      daemon_data = Qs::DaemonData.new(@config_hash)
      assert_true daemon_data.debug
      assert_equal daemon_data.logger, daemon_data.dwp_logger
    end

    should "look up a route using `route_for`" do
      exp_route = @routes.choice
      assert_equal exp_route, subject.route_for(exp_route.id)
    end

    should "raise a not found error using `route_for` with an invalid name" do
      assert_raises(Qs::NotFoundError) do
        subject.route_for(Factory.string)
      end
    end

    should "default its attrs when they aren't provided" do
      daemon_data = Qs::DaemonData.new
      assert_nil daemon_data.name
      assert_nil daemon_data.pid_file
      assert_nil daemon_data.shutdown_timeout

      assert_nil daemon_data.worker_class
      assert_equal({}, daemon_data.worker_params)
      assert_nil daemon_data.num_workers

      assert_equal [], daemon_data.error_procs

      assert_nil daemon_data.logger
      assert_equal [], daemon_data.queue_redis_keys

      assert_false daemon_data.verbose_logging

      assert_false daemon_data.debug
      assert_nil daemon_data.dwp_logger

      assert_equal({}, daemon_data.routes)
    end

  end

  TestHandler = Class.new

end
