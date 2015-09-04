require 'assert'
require 'qs/daemon'

require 'dat-worker-pool/worker_pool_spy'
require 'ns-options/assert_macros'
require 'thread'
require 'qs/client'
require 'qs/queue'
require 'qs/queue_item'

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

      @client_spy = nil
      Assert.stub(Qs::QsClient, :new) do |*args|
        @client_spy = ClientSpy.new(*args)
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
      @current_env_process_label = ENV['QS_PROCESS_LABEL']
      ENV['QS_PROCESS_LABEL'] = Factory.string

      @daemon = @daemon_class.new
    end
    teardown do
      ENV['QS_PROCESS_LABEL'] = @current_env_process_label
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
      assert_equal configuration.name,             data.name
      assert_equal configuration.process_label,    data.process_label
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
        :size    => subject.daemon_data.max_workers + 1
      })
      assert_equal exp, @client_spy.redis_config
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

    should "build and start a worker pool" do
      assert_not_nil @worker_pool_spy
      assert_equal @daemon_class.min_workers, @worker_pool_spy.min_workers
      assert_equal @daemon_class.max_workers, @worker_pool_spy.max_workers
      assert_equal 1, @worker_pool_spy.on_worker_error_callbacks.size
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
      @client_spy.append(@queue.redis_key, Factory.string)
      @thread.join(0.1)
      assert_empty @worker_pool_spy.work_items
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
      assert_equal exp, @worker_pool_spy.work_items.first
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

  class WorkerPoolWorkProcTests < InitSetupTests
    desc "worker pool work proc"
    setup do
      @ph_spy = nil
      Assert.stub(Qs::PayloadHandler, :new) do |*args|
        @ph_spy = PayloadHandlerSpy.new(*args)
      end

      @daemon = @daemon_class.new
      @thread = @daemon.start

      @queue_item = Qs::QueueItem.new(Factory.string, Factory.string)
      @worker_pool_spy.work_proc.call(@queue_item)
    end
    subject{ @daemon }

    should "build and run a payload handler" do
      assert_not_nil @ph_spy
      assert_equal subject.daemon_data, @ph_spy.daemon_data
      assert_equal @queue_item,         @ph_spy.queue_item
    end

  end

  class WorkerPoolOnWorkerErrorTests < InitSetupTests
    desc "worker pool on worker error proc"
    setup do
      @daemon = @daemon_class.new
      @thread = @daemon.start

      @exception  = Factory.exception
      @queue_item = Qs::QueueItem.new(Factory.string, Factory.string)
      @callback   = @worker_pool_spy.on_worker_error_callbacks.first
    end
    subject{ @daemon }

    should "requeue the queue item if it wasn't started" do
      @queue_item.started = false
      @callback.call('worker', @exception, @queue_item)
      call = @client_spy.calls.detect{ |c| c.command == :prepend }
      assert_not_nil call
      assert_equal @queue_item.queue_redis_key, call.args.first
      assert_equal @queue_item.encoded_payload, call.args.last
    end

    should "not requeue the queue item if it was started" do
      @queue_item.started = true
      @callback.call('worker', @exception, @queue_item)
      assert_nil @client_spy.calls.detect{ |c| c.command == :prepend }
    end

    should "do nothing if not passed a queue item" do
      assert_nothing_raised{ @callback.call(@exception, nil) }
    end

  end

  class StopTests < StartTests
    desc "and then stopped"
    setup do
      @queue_item = Qs::QueueItem.new(@queue.redis_key, Factory.string)
      @worker_pool_spy.add_work(@queue_item)

      @daemon.stop true
    end

    should "shutdown the worker pool" do
      assert_true @worker_pool_spy.shutdown_called
      assert_equal @daemon_class.shutdown_timeout, @worker_pool_spy.shutdown_timeout
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
      @worker_available = false
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
      @worker_pool_spy.add_work(@queue_item)

      @daemon.halt true
    end

    should "shutdown the worker pool with a 0 timeout" do
      assert_true @worker_pool_spy.shutdown_called
      assert_equal 0, @worker_pool_spy.shutdown_timeout
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
      @worker_available = false
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
      Assert.stub(@worker_pool_spy, :worker_available?){ raise RuntimeError }

      # cause the daemon to loop, its sleeping on the original block_dequeue
      # call that happened before the stub
      @queue_item = Qs::QueueItem.new(@queue.redis_key, Factory.string)
      @client_spy.append(@queue_item.queue_redis_key, @queue_item.encoded_payload)
    end

    should "shutdown the worker pool" do
      assert_true @worker_pool_spy.shutdown_called
      assert_equal @daemon_class.shutdown_timeout, @worker_pool_spy.shutdown_timeout
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
    should have_options :min_workers, :max_workers
    should have_options :verbose_logging, :logger
    should have_options :shutdown_timeout
    should have_accessors :process_label
    should have_accessors :init_procs, :error_procs
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
      assert_equal 1, config.min_workers
      assert_equal 4, config.max_workers
      assert_true config.verbose_logging
      assert_instance_of Qs::NullLogger, config.logger
      assert_nil subject.shutdown_timeout

      assert_nil config.process_label
      assert_equal [], config.init_procs
      assert_equal [], config.error_procs
      assert_equal [], config.queues
      assert_equal [], config.routes
    end

    should "prefer an env var for the label but fall back to the name option" do
      current_env_process_label = ENV['QS_PROCESS_LABEL']

      ENV['QS_PROCESS_LABEL'] = Factory.string
      config = Configuration.new(:name => Factory.string)
      assert_equal ENV['QS_PROCESS_LABEL'], config.process_label

      ENV['QS_PROCESS_LABEL'] = ''
      config = Configuration.new(:name => Factory.string)
      assert_equal config.name, config.process_label

      ENV.delete('QS_PROCESS_LABEL')
      config = Configuration.new(:name => Factory.string)
      assert_equal config.name, config.process_label

      ENV['QS_PROCESS_LABEL'] = current_env_process_label
    end

    should "not be valid by default" do
      assert_false subject.valid?
    end

    should "know its routes" do
      assert_equal subject.queues.map(&:routes).flatten, subject.routes
    end

    should "include some attrs (not just the options) in its hash" do
      config_hash = subject.to_hash

      assert_equal subject.process_label, config_hash[:process_label]
      assert_equal subject.error_procs,   config_hash[:error_procs]
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

  TestHandler = Class.new

  class PayloadHandlerSpy
    attr_reader :daemon_data, :queue_item, :run_called

    def initialize(daemon_data, queue_item)
      @daemon_data = daemon_data
      @queue_item  = queue_item
      @run_called  = false
    end

    def run
      @run_called = true
    end
  end

  class ClientSpy < Qs::TestClient
    attr_reader :calls

    def initialize(*args)
      super
      @calls = []
      @list  = []
      @mutex = Mutex.new
      @cv    = ConditionVariable.new
    end

    def block_dequeue(*args)
      @calls << Call.new(:block_dequeue, args)
      if @list.empty?
        @mutex.synchronize{ @cv.wait(@mutex) }
      end
      @list.shift
    end

    def append(*args)
      @calls << Call.new(:append, args)
      @list  << args
      @cv.signal
    end

    def prepend(*args)
      @calls << Call.new(:prepend, args)
      @list  << args
      @cv.signal
    end

    def clear(*args)
      @calls << Call.new(:clear, args)
    end

    def ping
      @calls << Call.new(:ping)
    end

    Call = Struct.new(:command, :args)
  end

end
