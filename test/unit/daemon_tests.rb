require 'assert'
require 'qs/daemon'

require 'dat-worker-pool/worker_pool_spy'
require 'hella-redis/connection_spy'
require 'ns-options/assert_macros'
require 'qs/queue'

module Qs::Daemon

  class UnitTests < Assert::Context
    desc "Qs::Daemon"
    setup do
      @daemon_class = Class.new{ include Qs::Daemon }
    end
    subject{ @daemon_class }

    should have_imeths :configuration
    should have_imeths :name, :pid_file
    should have_imeths :min_workers, :max_workers, :workers
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

    should "allow reading/writing its configuration min workers" do
      new_min_workers = Factory.integer
      subject.min_workers(new_min_workers)
      assert_equal new_min_workers, subject.configuration.min_workers
      assert_equal new_min_workers, subject.min_workers
    end

    should "allow reading/writing its configuration max workers" do
      new_max_workers = Factory.integer
      subject.max_workers(new_max_workers)
      assert_equal new_max_workers, subject.configuration.max_workers
      assert_equal new_max_workers, subject.max_workers
    end

    should "allow reading/writing its configuration workers" do
      new_workers = Factory.integer
      subject.workers(new_workers)
      assert_equal new_workers, subject.configuration.min_workers
      assert_equal new_workers, subject.configuration.max_workers
      assert_equal new_workers, subject.min_workers
      assert_equal new_workers, subject.max_workers
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

      @queue = Qs::Queue.new do
        name(Factory.string)
        job 'test', TestHandler.to_s
      end
      @daemon_class.name Factory.string
      @daemon_class.pid_file Factory.file_path
      @daemon_class.workers Factory.integer
      @daemon_class.verbose_logging Factory.boolean
      @daemon_class.shutdown_timeout Factory.integer
      @daemon_class.error{ Factory.string }
      @daemon_class.queue @queue

      @connection_spy = nil
      Assert.stub(HellaRedis::Connection, :new) do |*args|
        @connection_spy = ConnectionSpy.new(*args)
      end

      @worker_pool_spy = nil
      @worker_available = true
      Assert.stub(::DatWorkerPool, :new) do |*args, &block|
        @worker_pool_spy = DatWorkerPool::WorkerPoolSpy.new(*args, &block)
        @worker_pool_spy.worker_available = !!@worker_available
        @worker_pool_spy
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
    should have_imeths :name, :pid_file
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
      assert_equal configuration.name,             data.name
      assert_equal configuration.pid_file,         data.pid_file
      assert_equal configuration.min_workers,      data.min_workers
      assert_equal configuration.max_workers,      data.max_workers
      assert_equal configuration.verbose_logging,  data.verbose_logging
      assert_equal configuration.shutdown_timeout, data.shutdown_timeout
      assert_equal configuration.error_procs,      data.error_procs
      assert_equal [@queue.redis_key], data.queue_redis_keys
      assert_equal configuration.routes, data.routes.values
      assert_instance_of configuration.logger.class, data.logger
    end

    should "know its signal and queues redis keys" do
      data = subject.daemon_data
      expected = "signals:#{data.name}-#{Socket.gethostname}-#{::Process.pid}"
      assert_equal expected, subject.signals_redis_key
      assert_equal data.queue_redis_keys, subject.queue_redis_keys
    end

    should "know its name and pid file" do
      data = subject.daemon_data
      assert_equal data.name,     subject.name
      assert_equal data.pid_file, subject.pid_file
    end

    should "build a redis connection" do
      assert_not_nil @connection_spy
      exp = Qs.redis_config.merge({
        :timeout => 1,
        :size    => 2
      })
      assert_equal exp, @connection_spy.config
    end

    should "not be running by default" do
      assert_false subject.running?
    end

  end

  class StartTests < InitTests
    desc "and started"
    setup do
      @thread = @daemon.start
      sleep 0.1
    end

    should "return the thread that is running the daemon" do
      assert_instance_of Thread, @thread
      assert_true @thread.alive?
    end

    should "be running" do
      assert_true subject.running?
    end

    should "clear the signals list in redis" do
      call = @connection_spy.redis_calls.first
      assert_equal :del, call.command
      assert_equal [subject.signals_redis_key], call.args
    end

    should "build and start a worker pool" do
      assert_not_nil @worker_pool_spy
      assert_equal @daemon_class.min_workers, @worker_pool_spy.min_workers
      assert_equal @daemon_class.max_workers, @worker_pool_spy.max_workers
      assert_equal 1, @worker_pool_spy.on_queue_pop_callbacks.size
      assert_equal 1, @worker_pool_spy.on_worker_sleep_callbacks.size
      assert_true @worker_pool_spy.start_called
    end

  end

  class RunningWithoutAvailableWorkerTests < InitSetupTests
    desc "running without an available worker"
    setup do
      @worker_available = false

      @daemon = @daemon_class.new
      @thread = @daemon.start
    end
    subject{ @daemon }

    should "sleep its thread and not add work to its worker pool" do
      @thread.join(0.1)
      assert_equal 'sleep', @thread.status
      @connection_spy.add_item_to_list(@queue.redis_key, Factory.string)
      @thread.join(0.1)
      assert_empty @worker_pool_spy.work_items
    end

  end

  class RunningWithWorkerAndWorkTests < InitSetupTests
    desc "running with a worker available and work"
    setup do
      @daemon = @daemon_class.new
      @thread = @daemon.start

      @serialized_payload = Factory.string
      @connection_spy.add_item_to_list(@queue.redis_key, @serialized_payload)
    end
    subject{ @daemon }

    should "call brpop on its redis connection and add work to the worker pool" do
      call = @connection_spy.redis_calls.last
      assert_equal :brpop, call.command
      exp = [subject.signals_redis_key, subject.queue_redis_keys, 0].flatten
      assert_equal exp, call.args
      exp = RedisItem.new(@queue.redis_key, @serialized_payload)
      assert_equal exp, @worker_pool_spy.work_items.first
    end

  end

  class WorkerPoolWorkProcTests < InitSetupTests
    desc "worker pool work proc"
    setup do
      @ph_spy = nil
      Assert.stub(Qs::PayloadHandler, :new) do |*args|
        @ph_spy = PayloadHandlerSpy.new(*args)
      end

      @daemon = @daemon_class.new
      @thread = @daemon.start

      @redis_item = RedisItem.new(Factory.string, Factory.string)
      @worker_pool_spy.work_proc.call(@redis_item)
    end
    subject{ @daemon }

    should "build and run a payload handler" do
      assert_not_nil @ph_spy
      assert_equal subject.daemon_data,            @ph_spy.daemon_data
      assert_equal @redis_item.queue_key,          @ph_spy.queue_redis_key
      assert_equal @redis_item.serialized_payload, @ph_spy.serialized_payload
    end

  end

  class StopTests < StartTests
    desc "and then stopped"
    setup do
      Assert.stub(SystemTimer, :timeout_after).with(
        @daemon_class.shutdown_timeout
      ){ |&block| block.call }

      @daemon.stop true
    end

    should "shutdown the worker pool" do
      assert_true @worker_pool_spy.shutdown_called
      assert_equal @daemon_class.shutdown_timeout, @worker_pool_spy.shutdown_timeout
    end

    should "stop the work loop thread" do
      assert_false @thread.alive?
    end

    should "not be running" do
      assert_equal false, subject.running?
    end

  end

  class StoppedWithWorkAndNoShutdownTimeoutTests < InitSetupTests
    desc "and stopped without a shutdown timeout and work on the pool"
    setup do
      @daemon_class.shutdown_timeout nil
      @daemon = @daemon_class.new
      @thread = @daemon.start
      sleep 0.1
      @worker_pool_spy.add_work(Factory.string)
      @daemon.stop
    end
    teardown do
      @daemon.halt true
    end

    should "shutdown the worker pool once the work has been processed" do
      assert_false @worker_pool_spy.shutdown_called
      @worker_pool_spy.pop_work
      @thread.join
      assert_true @worker_pool_spy.shutdown_called
      assert_nil @worker_pool_spy.shutdown_timeout
    end

  end

  class StoppedWithWorkAndShutdownTimeoutTests < InitSetupTests
    desc "and stopped with a shutdown timeout and work on the pool"
    setup do
      @daemon_class.shutdown_timeout 0.5
      @daemon = @daemon_class.new
      @thread = @daemon.start
      @worker_pool_spy.add_work(Factory.string)
      @daemon.stop
    end
    teardown do
      @daemon.halt true
    end

    should "shutdown the worker pool once the work has been processed" do
      @worker_pool_spy.work_items.pop
      @thread.join
      assert_true @worker_pool_spy.shutdown_called
      assert_equal @daemon_class.shutdown_timeout, @worker_pool_spy.shutdown_timeout
    end

    should "force shutdown the worker pool if the work is never processed" do
      @thread.join
      assert_true @worker_pool_spy.shutdown_called
      assert_equal 0, @worker_pool_spy.shutdown_timeout
    end

  end

  class StopWhileWaitingForWorkerTests < InitSetupTests
    desc "stopped while waiting for a worker"
    setup do
      @worker_available = false
      @daemon = @daemon_class.new
      @thread = @daemon.start
      @daemon.stop(true)
    end
    subject{ @daemon }

    should "not be running" do
      assert_equal false, subject.running?
    end

  end

  class HaltTests < StartTests
    desc "and then halted"
    setup do
      @daemon.halt true
    end

    should "not shutdown the worker pool" do
      assert_false @worker_pool_spy.shutdown_called
    end

    should "stop the work loop thread" do
      assert_false @thread.alive?
    end

    should "not be running" do
      assert_equal false, subject.running?
    end

  end

  class HaltWhileWaitingForWorkerTests < InitSetupTests
    desc "halted while waiting for a worker"
    setup do
      @worker_available = false
      @daemon = @daemon_class.new
      @thread = @daemon.start
      @daemon.halt(true)
    end
    subject{ @daemon }

    should "not be running" do
      assert_equal false, subject.running?
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
    should have_options :min_workers, :max_workers
    should have_options :verbose_logging, :logger
    should have_options :shutdown_timeout
    should have_accessors :init_procs, :error_procs
    should have_accessors :queues
    should have_imeths :routes
    should have_imeths :to_hash
    should have_imeths :valid?, :validate!

    should "be an ns-options proxy" do
      assert_includes NsOptions::Proxy, subject.class
    end

    should "default its options" do
      config = Configuration.new
      assert_nil config.name
      assert_nil config.pid_file
      assert_equal 1, config.min_workers
      assert_equal 4, config.max_workers
      assert_true config.verbose_logging
      assert_instance_of Qs::NullLogger, config.logger
      assert_nil subject.shutdown_timeout
      assert_equal [], config.init_procs
      assert_equal [], config.error_procs
      assert_equal [], config.queues
      assert_equal [], config.routes
    end

    should "not be valid by default" do
      assert_false subject.valid?
    end

    should "know its routes" do
      assert_equal subject.queues.map(&:routes).flatten, subject.routes
    end

    should "include its error procs, queue redis keys and routes in its hash" do
      config_hash = subject.to_hash
      assert_equal subject.error_procs, config_hash[:error_procs]
      expected = subject.queues.map(&:redis_key)
      assert_equal expected, config_hash[:queue_redis_keys]
      assert_equal subject.routes, config_hash[:routes]
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

  class IOPipeTests < UnitTests
    desc "IOPipe"
    setup do
      @io = IOPipe.new
    end
    subject{ @io }

    should have_readers :reader, :writer
    should have_imeths :wait, :signal
    should have_imeths :setup, :teardown

    should "default its reader and writer" do
      assert_same IOPipe::NULL, subject.reader
      assert_same IOPipe::NULL, subject.writer
    end

    should "be able to wait until signalled" do
      subject.setup

      thread = Thread.new{ subject.wait }
      thread.join(0.1)
      assert_equal 'sleep', thread.status

      subject.signal
      thread.join
      assert_false thread.status
    end

    should "set its reader and writer to an IO pipe when setup" do
      subject.setup
      assert_instance_of ::IO, subject.reader
      assert_instance_of ::IO, subject.writer
    end

    should "close its reader/writer and set them to defaults when torn down" do
      subject.setup
      reader = subject.reader
      writer = subject.writer

      subject.teardown
      assert_true reader.closed?
      assert_true writer.closed?
      assert_same IOPipe::NULL, subject.reader
      assert_same IOPipe::NULL, subject.writer
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

  TestHandler = Class.new

  class PayloadHandlerSpy
    attr_reader :daemon_data, :queue_redis_key, :serialized_payload
    attr_reader :run_called

    def initialize(daemon_data, queue_redis_key, serialized_payload)
      @daemon_data        = daemon_data
      @queue_redis_key    = queue_redis_key
      @serialized_payload = serialized_payload
      @run_called = false
    end

    def run
      @run_called = true
    end
  end

  class ConnectionSpy < HellaRedis::ConnectionSpy
    def initialize(config)
      super(config, RedisSpy.new(config))
    end

    def add_item_to_list(key, value)
      self.redis_spy.lpush(key, value)
    end
  end

  class RedisSpy < HellaRedis::RedisSpy
    attr_reader :list

    def initialize(config)
      super(config)
      @list = []
      @mutex = Mutex.new
      @condition_variable = ConditionVariable.new
    end

    def lpush(*args)
      super(*args)
      self.list.unshift(args)
      @condition_variable.signal
    end

    def brpop(*args)
      super(*args)
      if self.list.empty?
        @mutex.synchronize{ @condition_variable.wait(@mutex) }
      end
      self.list.pop
    end
  end

end
