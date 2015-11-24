require 'assert'
require 'qs/daemon_data'

require 'qs/queue'
require 'qs/route'

class Qs::DaemonData

  class UnitTests < Assert::Context
    desc "Qs::DaemonData"
    setup do
      @current_env_process_label = ENV['QS_PROCESS_LABEL']
      ENV['QS_PROCESS_LABEL'] = Factory.string

      @routes = (0..Factory.integer(3)).map do
        Qs::Route.new(Factory.string, TestHandler.to_s).tap(&:validate!)
      end

      @config_hash = {
        :name             => Factory.string,
        :pid_file         => Factory.file_path,
        :worker_class     => Class.new,
        :worker_params    => { Factory.string => Factory.string },
        :num_workers      => Factory.integer,
        :logger           => Factory.string,
        :verbose_logging  => Factory.boolean,
        :shutdown_timeout => Factory.integer,
        :error_procs      => [ proc{ Factory.string } ],
        :queue_redis_keys => Factory.integer(3).times.map{ Factory.string },
        :routes           => @routes
      }
      @daemon_data = Qs::DaemonData.new(@config_hash)
    end
    teardown do
      ENV['QS_PROCESS_LABEL'] = @current_env_process_label
    end
    subject{ @daemon_data }

    should have_readers :name, :process_label
    should have_readers :pid_file
    should have_readers :worker_class, :worker_params
    should have_readers :num_workers
    should have_readers :logger, :verbose_logging
    should have_readers :shutdown_timeout
    should have_readers :error_procs
    should have_readers :queue_redis_keys, :routes
    should have_imeths :route_for

    should "know its attributes" do
      h = @config_hash
      assert_equal h[:name],             subject.name
      assert_equal h[:pid_file],         subject.pid_file
      assert_equal h[:worker_class],     subject.worker_class
      assert_equal h[:worker_params],    subject.worker_params
      assert_equal h[:num_workers],      subject.num_workers
      assert_equal h[:logger],           subject.logger
      assert_equal h[:verbose_logging],  subject.verbose_logging
      assert_equal h[:shutdown_timeout], subject.shutdown_timeout
      assert_equal h[:error_procs],      subject.error_procs
      assert_equal h[:queue_redis_keys], subject.queue_redis_keys
    end

    should "use process label env var if set" do
      ENV['QS_PROCESS_LABEL'] = Factory.string
      daemon_data = Qs::DaemonData.new(@config_hash)
      assert_equal ENV['QS_PROCESS_LABEL'], daemon_data.process_label

      ENV['QS_PROCESS_LABEL'] = ""
      daemon_data = Qs::DaemonData.new(@config_hash)
      assert_equal @config_hash[:name], daemon_data.process_label

      ENV.delete('QS_PROCESS_LABEL')
      daemon_data = Qs::DaemonData.new(@config_hash)
      assert_equal @config_hash[:name], daemon_data.process_label
    end

    should "build a routes lookup hash" do
      expected = @routes.inject({}){ |h, r| h.merge(r.id => r) }
      assert_equal expected, subject.routes
    end

    should "allow looking up a route using `route_for`" do
      exp_route = @routes.choice
      route = subject.route_for(exp_route.id)
      assert_equal exp_route, route
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
      assert_nil daemon_data.worker_class
      assert_equal({}, daemon_data.worker_params)
      assert_nil daemon_data.num_workers
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
