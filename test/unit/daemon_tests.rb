require 'assert'
require 'qs/daemon'

require 'dat-worker-pool/worker_pool_spy'
require 'ns-options/assert_macros'
require 'thread'
require 'qs/client'
require 'qs/queue'
require 'qs/queue_item'
require 'test/support/client_spy'

module Qs::Daemon

  class UnitTests < Assert::Context
    desc "Qs::Daemon"
    setup do
      @daemon_class = Class.new{ include Qs::Daemon }
    end
    subject{ @daemon_class }

    should have_imeths :configuration
    should have_imeths :name, :pid_file
    should have_imeths :worker_class, :worker_params
    should have_imeths :num_workers, :workers
    should have_imeths :verbose_logging, :logger
    should have_imeths :shutdown_timeout
    should have_imeths :init, :error, :queue

    should "know its configuration" do
      config = subject.configuration
      assert_instance_of Configuration, config
      assert_same config, subject.configuration
    end

    should "allow reading/writing its configuration name" do
      new_name = Factory.string
      subject.name(new_name)
      assert_equal new_name, subject.configuration.name
      assert_equal new_name, subject.name
    end

    should "allow reading/writing its configuration pid file" do
      new_pid_file = Factory.string
      subject.pid_file(new_pid_file)
      expected = Pathname.new(new_pid_file)
      assert_equal expected, subject.configuration.pid_file
      assert_equal expected, subject.pid_file
    end

    should "allow reading/writing its configuration worker class" do
      new_worker_class = Class.new
      subject.worker_class(new_worker_class)
      assert_equal new_worker_class, subject.configuration.worker_class
      assert_equal new_worker_class, subject.worker_class
    end

    should "allow reading/writing its configuration worker params" do
      new_worker_params = { Factory.string => Factory.string }
      subject.worker_params(new_worker_params)
      assert_equal new_worker_params, subject.configuration.worker_params
      assert_equal new_worker_params, subject.worker_params
    end

    should "allow reading/writing its configuration num workers" do
      new_num_workers = Factory.integer
      subject.num_workers(new_num_workers)
      assert_equal new_num_workers, subject.configuration.num_workers
      assert_equal new_num_workers, subject.num_workers
    end

    should "alias workers as num workers" do
      new_workers = Factory.integer
      subject.workers(new_workers)
      assert_equal new_workers, subject.configuration.num_workers
      assert_equal new_workers, subject.workers
    end

    should "allow reading/writing its configuration verbose logging" do
      new_verbose = Factory.boolean
      subject.verbose_logging(new_verbose)
      assert_equal new_verbose, subject.configuration.verbose_logging
      assert_equal new_verbose, subject.verbose_logging
    end

    should "allow reading/writing its configuration logger" do
      new_logger = Factory.string
      subject.logger(new_logger)
      assert_equal new_logger, subject.configuration.logger
      assert_equal new_logger, subject.logger
    end

    should "allow reading/writing its configuration shutdown timeout" do
      new_shutdown_timeout = Factory.integer
      subject.shutdown_timeout(new_shutdown_timeout)
      assert_equal new_shutdown_timeout, subject.configuration.shutdown_timeout
      assert_equal new_shutdown_timeout, subject.shutdown_timeout
    end

    should "allow adding init procs to its configuration" do
      new_init_proc = proc{ Factory.string }
      subject.init(&new_init_proc)
      assert_includes new_init_proc, subject.configuration.init_procs
    end

    should "allow adding error procs to its configuration" do
      new_error_proc = proc{ Factory.string }
      subject.error(&new_error_proc)
      assert_includes new_error_proc, subject.configuration.error_procs
    end

    should "allow adding queues to its configuration" do
      new_queue = Factory.string
      subject.queue(new_queue)
      assert_includes new_queue, subject.configuration.queues
    end

  end

  class InitSetupTests < UnitTests
    setup do
      @qs_init_called = false
      Assert.stub(Qs, :init){ @qs_init_called = true }

      @daemon_class.name Factory.string
      @daemon_class.pid_file Factory.file_path
      @daemon_class.worker_params(Factory.string => Factory.string)
      @daemon_class.workers Factory.integer
      @daemon_class.verbose_logging Factory.boolean
      @daemon_class.shutdown_timeout Factory.integer
      @daemon_class.error{ Factory.string }

      @queue = Qs::Queue.new do
        name(Factory.string)
        job 'test', TestHandler.to_s
      end
      @daemon_class.queue @queue

      @client_spy = nil
      Assert.stub(Qs::QsClient, :new) do |*args|
        @client_spy = ClientSpy.new(*args)
      end

      @worker_available = WorkerAvailable.new
      Assert.stub(WorkerAvailable, :new){ @worker_available }

      @wp_spy             = nil
      @wp_worker_available = true
      Assert.stub(DatWorkerPool, :new) do |*args|
        @wp_spy = DatWorkerPool::WorkerPoolSpy.new(*args)
        @wp_spy.worker_available = !!@wp_worker_available
        @wp_spy
      end
    end
    teardown do
      @daemon.halt(true) rescue false
    end

  end

  class InitTests < InitSetupTests
    desc "when init"
    setup do
      @daemon = @daemon_class.new
    end
    subject{ @daemon }

    should have_readers :daemon_data, :logger
    should have_readers :signals_redis_key, :queue_redis_keys
    should have_imeths :name, :process_label, :pid_file
    should have_imeths :running?
    should have_imeths :start, :stop, :halt

    should "validate its configuration" do
      assert_true @daemon_class.configuration.valid?
    end

    should "init Qs" do
      assert_true @qs_init_called
    end

    should "know its daemon data" do
      configuration = @daemon_class.configuration
      data = subject.daemon_data

      assert_instance_of Qs::DaemonData, data
      assert_equal configuration.name,          data.name
      assert_equal configuration.pid_file,      data.pid_file
      assert_equal configuration.worker_class,  data.worker_class
      assert_equal configuration.worker_params, data.worker_params
      assert_equal configuration.num_workers,   data.num_workers

      assert_equal configuration.verbose_logging,  data.verbose_logging
      assert_equal configuration.shutdown_timeout, data.shutdown_timeout
      assert_equal configuration.error_procs,      data.error_procs

      assert_equal [@queue.redis_key],   data.queue_redis_keys
      assert_equal configuration.routes, data.routes.values

      assert_instance_of configuration.logger.class, data.logger
    end

    should "know its signal and queues redis keys" do
      data = subject.daemon_data
      expected = "signals:#{data.name}-#{Socket.gethostname}-#{::Process.pid}"
      assert_equal expected, subject.signals_redis_key
      assert_equal data.queue_redis_keys, subject.queue_redis_keys
    end

    should "know its name, process label and pid file" do
      data = subject.daemon_data
      assert_equal data.name,          subject.name
      assert_equal data.process_label, subject.process_label
      assert_equal data.pid_file,      subject.pid_file
    end

    should "build a client" do
      assert_not_nil @client_spy
      exp = Qs.redis_config.merge({
        :timeout => 1,
        :size    => subject.daemon_data.num_workers + 1
      })
      assert_equal exp, @client_spy.redis_config
    end

    should "build a worker pool" do
      data = subject.daemon_data

      assert_not_nil @wp_spy
      assert_equal data.worker_class, @wp_spy.worker_class
      assert_equal data.dwp_logger,   @wp_spy.logger
      assert_equal data.num_workers,  @wp_spy.num_workers
      exp = data.worker_params.merge({
        :qs_daemon_data      => data,
        :qs_client           => @client_spy,
        :qs_worker_available => @worker_available,
        :qs_logger           => data.logger
      })
      assert_equal exp, @wp_spy.worker_params
      assert_false @wp_spy.start_called
    end

    should "not be running by default" do
      assert_false subject.running?
    end

  end

  class StartTests < InitTests
    desc "and started"
    setup do
      @thread = @daemon.start
      @thread.join 0.1
    end

    should "ping redis" do
      call = @client_spy.calls.first
      assert_equal :ping, call.command
    end

    should "return the thread that is running the daemon" do
      assert_instance_of Thread, @thread
      assert_true @thread.alive?
    end

    should "be running" do
      assert_true subject.running?
    end

    should "clear the signals list in redis" do
      call = @client_spy.calls.find{ |c| c.command == :clear }
      assert_not_nil call
      assert_equal [subject.signals_redis_key], call.args
    end

    should "start its worker pool" do
      assert_true @wp_spy.start_called
    end

  end

  class RunningWithoutAvailableWorkerTests < InitSetupTests
    desc "running without an available worker"
    setup do
      @wp_worker_available = false

      @daemon = @daemon_class.new
      @thread = @daemon.start
    end
    subject{ @daemon }

    should "sleep its thread and not add work to its worker pool" do
      @thread.join(0.1)
      assert_equal 'sleep', @thread.status
      @client_spy.append(@queue.redis_key, Factory.string)
      @thread.join(0.1)
      assert_empty @wp_spy.work_items
    end

  end

  class RunningWithWorkerAndWorkTests < InitSetupTests
    desc "running with a worker available and work"
    setup do
      @daemon = @daemon_class.new
      @thread = @daemon.start

      @encoded_payload = Factory.string
      @client_spy.append(@queue.redis_key, @encoded_payload)
    end
    subject{ @daemon }

    should "call dequeue on its client and add work to the worker pool" do
      call = @client_spy.calls.last
      assert_equal :block_dequeue, call.command
      exp = [subject.signals_redis_key, subject.queue_redis_keys, 0].flatten
      assert_equal exp, call.args
      exp = Qs::QueueItem.new(@queue.redis_key, @encoded_payload)
      assert_equal exp, @wp_spy.work_items.first
    end

  end

  class RunningWithErrorWhileDequeuingTests < InitSetupTests
    desc "running with an error while dequeueing"
    setup do
      @daemon = @daemon_class.new
      @thread = @daemon.start

      @block_dequeue_calls = 0
      Assert.stub(@client_spy, :block_dequeue) do
        @block_dequeue_calls += 1
        raise RuntimeError
      end
      # cause the daemon to loop, its sleeping on the original block_dequeue
      # call that happened before the stub
      @client_spy.append(@queue.redis_key, Factory.string)
      @thread.join(0.1)
    end
    subject{ @daemon }

    should "not cause the thread to exit" do
      assert_true @thread.alive?
      assert_equal 1, @block_dequeue_calls
      @thread.join(1)
      assert_true @thread.alive?
      assert_equal 2, @block_dequeue_calls
    end

  end

  class RunningWithMultipleQueuesTests < InitSetupTests
    desc "running with multiple queues"
    setup do
      @other_queue = Qs::Queue.new{ name(Factory.string) }
      @daemon_class.queue @other_queue
      @daemon = @daemon_class.new

      @shuffled_keys = @daemon.queue_redis_keys + [Factory.string]
      Assert.stub(@daemon.queue_redis_keys, :shuffle){ @shuffled_keys }

      @thread = @daemon.start
    end
    subject{ @daemon }

    should "shuffle the queue keys to avoid queue starvation" do
      call = @client_spy.calls.last
      assert_equal :block_dequeue, call.command
      exp = [subject.signals_redis_key, @shuffled_keys, 0].flatten
      assert_equal exp, call.args
    end

  end

  class StopTests < StartTests
    desc "and then stopped"
    setup do
      @queue_item = Qs::QueueItem.new(@queue.redis_key, Factory.string)
      @wp_spy.push(@queue_item)

      @daemon.stop true
    end

    should "shutdown the worker pool" do
      assert_true @wp_spy.shutdown_called
      assert_equal @daemon_class.shutdown_timeout, @wp_spy.shutdown_timeout
    end

    should "requeue any work left on the pool" do
      call = @client_spy.calls.last
      assert_equal :prepend, call.command
      assert_equal @queue_item.queue_redis_key, call.args.first
      assert_equal @queue_item.encoded_payload, call.args.last
    end

    should "stop the work loop thread" do
      assert_false @thread.alive?
    end

    should "not be running" do
      assert_false subject.running?
    end

  end

  class StopWhileWaitingForWorkerTests < InitSetupTests
    desc "stopped while waiting for a worker"
    setup do
      @wp_worker_available = false
      @daemon = @daemon_class.new
      @thread = @daemon.start
      @daemon.stop(true)
    end
    subject{ @daemon }

    should "not be running" do
      assert_false subject.running?
    end

  end

  class HaltTests < StartTests
    desc "and then halted"
    setup do
      @queue_item = Qs::QueueItem.new(@queue.redis_key, Factory.string)
      @wp_spy.push(@queue_item)

      @daemon.halt true
    end

    should "shutdown the worker pool with a 0 timeout" do
      assert_true @wp_spy.shutdown_called
      assert_equal 0, @wp_spy.shutdown_timeout
    end

    should "requeue any work left on the pool" do
      call = @client_spy.calls.last
      assert_equal :prepend, call.command
      assert_equal @queue_item.queue_redis_key, call.args.first
      assert_equal @queue_item.encoded_payload, call.args.last
    end

    should "stop the work loop thread" do
      assert_false @thread.alive?
    end

    should "not be running" do
      assert_false subject.running?
    end

  end

  class HaltWhileWaitingForWorkerTests < InitSetupTests
    desc "halted while waiting for a worker"
    setup do
      @wp_worker_available = false
      @daemon = @daemon_class.new
      @thread = @daemon.start
      @daemon.halt(true)
    end
    subject{ @daemon }

    should "not be running" do
      assert_false subject.running?
    end

  end

  class WorkLoopErrorTests < StartTests
    desc "with a work loop error"
    setup do
      # cause a non-dequeue error
      Assert.stub(@wp_spy, :worker_available?){ raise RuntimeError }

      # cause the daemon to loop, it's sleeping on the original `block_dequeue`
      # call that happened before the stub
      @queue_item = Qs::QueueItem.new(@queue.redis_key, Factory.string)
      @client_spy.append(@queue_item.queue_redis_key, @queue_item.encoded_payload)
      @thread.join
    end

    should "shutdown the worker pool" do
      assert_true @wp_spy.shutdown_called
      assert_equal @daemon_class.shutdown_timeout, @wp_spy.shutdown_timeout
    end

    should "requeue any work left on the pool" do
      call = @client_spy.calls.last
      assert_equal :prepend, call.command
      assert_equal @queue_item.queue_redis_key, call.args.first
      assert_equal @queue_item.encoded_payload, call.args.last
    end

    should "stop the work loop thread" do
      assert_false @thread.alive?
    end

    should "not be running" do
      assert_false subject.running?
    end

  end

  class ConfigurationTests < UnitTests
    include NsOptions::AssertMacros

    desc "Configuration"
    setup do
      @queue = Qs::Queue.new do
        name Factory.string
        job_handler_ns 'Qs::Daemon'
        job 'test', 'TestHandler'
      end

      @configuration = Configuration.new.tap do |c|
        c.name Factory.string
        c.queues << @queue
      end
    end
    subject{ @configuration }

    should have_options :name, :pid_file
    should have_options :num_workers
    should have_options :verbose_logging, :logger
    should have_options :shutdown_timeout
    should have_accessors :init_procs, :error_procs
    should have_accessors :worker_class, :worker_params
    should have_accessors :queues
    should have_imeths :routes
    should have_imeths :to_hash
    should have_imeths :valid?, :validate!

    should "be an ns-options proxy" do
      assert_includes NsOptions::Proxy, subject.class
    end

    should "default its options and attrs" do
      config = Configuration.new
      assert_nil config.name
      assert_nil config.pid_file
      assert_equal 4, config.num_workers
      assert_true config.verbose_logging
      assert_instance_of Qs::NullLogger, config.logger
      assert_nil subject.shutdown_timeout

      assert_equal [], config.init_procs
      assert_equal [], config.error_procs
      assert_equal DefaultWorker, config.worker_class
      assert_nil config.worker_params
      assert_equal [], config.queues
      assert_equal [], config.routes
    end

    should "not be valid by default" do
      assert_false subject.valid?
    end

    should "know its routes" do
      assert_equal subject.queues.map(&:routes).flatten, subject.routes
    end

    should "include some attrs (not just the options) in its hash" do
      config_hash = subject.to_hash

      assert_equal subject.error_procs,   config_hash[:error_procs]
      assert_equal subject.worker_class,  config_hash[:worker_class]
      assert_equal subject.worker_params, config_hash[:worker_params]
      assert_equal subject.routes,        config_hash[:routes]

      exp = subject.queues.map(&:redis_key)
      assert_equal exp, config_hash[:queue_redis_keys]
    end

    should "call its init procs when validated" do
      called = false
      subject.init_procs << proc{ called = true }
      subject.validate!
      assert_true called
    end

    should "ensure its required options have been set when validated" do
      subject.name = nil
      assert_raises(InvalidError){ subject.validate! }
      subject.name = Factory.string

      subject.queues = []
      assert_raises(InvalidError){ subject.validate! }
      subject.queues << @queue

      assert_nothing_raised{ subject.validate! }
    end

    should "validate its routes when validated" do
      subject.routes.each{ |route| assert_nil route.handler_class }
      subject.validate!
      subject.routes.each{ |route| assert_not_nil route.handler_class }
    end

    should "validate its worker class when validated" do
      subject.worker_class = Module.new
      assert_raises(InvalidError){ subject.validate! }

      subject.worker_class = Class.new
      assert_raises(InvalidError){ subject.validate! }
    end

    should "be valid after being validated" do
      assert_false subject.valid?
      subject.validate!
      assert_true subject.valid?
    end

    should "only be able to be validated once" do
      called = 0
      subject.init_procs << proc{ called += 1 }
      subject.validate!
      assert_equal 1, called
      subject.validate!
      assert_equal 1, called
    end

  end

  class SignalTests < UnitTests
    desc "Signal"
    setup do
      @signal = Signal.new(:stop)
    end
    subject{ @signal }

    should have_imeths :set, :start?, :stop?, :halt?

    should "allow setting it to start" do
      subject.set :start
      assert_true subject.start?
      assert_false subject.stop?
      assert_false subject.halt?
    end

    should "allow setting it to stop" do
      subject.set :stop
      assert_false subject.start?
      assert_true subject.stop?
      assert_false subject.halt?
    end

    should "allow setting it to halt" do
      subject.set :halt
      assert_false subject.start?
      assert_false subject.stop?
      assert_true subject.halt?
    end

  end

  class WorkerAvailableTests < UnitTests
    desc "WorkerAvailable"
    setup do
      @worker_available = WorkerAvailable.new
    end
    subject{ @worker_available }

    should have_imeths :wait, :signal

    should "allow waiting and signalling" do
      thread = Thread.new{ subject.wait }
      assert_equal 'sleep', thread.status
      subject.signal
      assert_equal false, thread.status # dead, done running
    end

  end

  TestHandler = Class.new

end
