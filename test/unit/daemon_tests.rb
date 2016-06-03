require 'assert'
require 'qs/daemon'

require 'dat-worker-pool/worker_pool_spy'
require 'much-plugin'
require 'thread'
require 'qs/client'
require 'qs/logger'
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

    should have_imeths :config
    should have_imeths :name, :pid_file, :shutdown_timeout
    should have_imeths :worker_class, :worker_params, :num_workers, :workers
    should have_imeths :init, :error, :logger, :queue, :queues
    should have_imeths :verbose_logging

    should "use much-plugin" do
      assert_includes MuchPlugin, Qs::Daemon
    end

    should "allow setting its config values" do
      config = subject.config

      exp = Factory.string
      subject.name exp
      assert_equal exp, config.name

      exp = Factory.file_path
      subject.pid_file exp
      assert_equal exp, config.pid_file

      exp = Factory.integer
      subject.shutdown_timeout exp
      assert_equal exp, config.shutdown_timeout

      exp = Class.new
      subject.worker_class exp
      assert_equal exp, subject.config.worker_class

      exp = { Factory.string => Factory.string }
      subject.worker_params exp
      assert_equal exp, subject.config.worker_params

      exp = Factory.integer
      subject.num_workers(exp)
      assert_equal exp, subject.config.num_workers
      assert_equal exp, subject.workers

      exp = proc{ }
      assert_equal 0, config.init_procs.size
      subject.init(&exp)
      assert_equal 1, config.init_procs.size
      assert_equal exp, config.init_procs.first

      exp = proc{ }
      assert_equal 0, config.error_procs.size
      subject.error(&exp)
      assert_equal 1, config.error_procs.size
      assert_equal exp, config.error_procs.first

      exp = Logger.new(STDOUT)
      subject.logger exp
      assert_equal exp, config.logger

      exp = Factory.string
      subject.queue(exp)
      assert_equal [exp], subject.config.queues

      exp = Factory.boolean
      subject.verbose_logging exp
      assert_equal exp, config.verbose_logging
    end

  end

  class InitSetupTests < UnitTests
    setup do
      @qs_init_called = false
      Assert.stub(Qs, :init){ @qs_init_called = true }

      @daemon_class.name Factory.string
      @daemon_class.pid_file Factory.file_path
      @daemon_class.shutdown_timeout Factory.integer
      @daemon_class.worker_params(Factory.string => Factory.string)
      @daemon_class.num_workers Factory.integer
      @daemon_class.verbose_logging Factory.boolean
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

      @wp_spy              = nil
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

    should have_readers :daemon_data, :signals_redis_key
    should have_imeths :name, :process_label, :pid_file
    should have_imeths :logger, :queue_redis_keys
    should have_imeths :running?
    should have_imeths :start, :stop, :halt

    should "have validated its config" do
      assert_true @daemon_class.config.valid?
    end

    should "have initialized Qs" do
      assert_true @qs_init_called
    end

    should "know its daemon data" do
      config = @daemon_class.config
      data   = subject.daemon_data

      assert_instance_of Qs::DaemonData, data

      assert_equal config.name,             data.name
      assert_equal config.pid_file,         data.pid_file
      assert_equal config.shutdown_timeout, data.shutdown_timeout
      assert_equal config.worker_class,     data.worker_class
      assert_equal config.worker_params,    data.worker_params
      assert_equal config.num_workers,      data.num_workers
      assert_equal config.error_procs,      data.error_procs

      assert_instance_of config.logger.class, data.logger

      assert_equal config.queues.size,     data.queue_redis_keys.size
      assert_equal config.verbose_logging, data.verbose_logging

      assert_equal config.routes, data.routes.values
    end

    should "know its signals redis keys" do
      data = subject.daemon_data
      exp = "signals:#{data.name}-#{Socket.gethostname}-#{::Process.pid}"
      assert_equal exp, subject.signals_redis_key
    end

    should "build a client" do
      assert_not_nil @client_spy
      exp = Qs.redis_config.merge({
        :timeout => 1,
        :size    => subject.daemon_data.num_workers + 1
      })
      assert_equal exp, @client_spy.redis_config
    end

    should "build a dat-worker-pool worker pool" do
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

    should "demeter its daemon data" do
      data = subject.daemon_data

      assert_equal data.name,             subject.name
      assert_equal data.process_label,    subject.process_label
      assert_equal data.pid_file,         subject.pid_file
      assert_equal data.logger,           subject.logger
      assert_equal data.queue_redis_keys, subject.queue_redis_keys
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

  class ConfigTests < UnitTests
    desc "Config"
    setup do
      @queue = Qs::Queue.new do
        name Factory.string
        job_handler_ns 'Qs::Daemon'
        job 'test', 'TestHandler'
      end

      @config_class = Config
      @config = Config.new

      # @configuration = Configuration.new.tap do |c|
      #   c.name Factory.string
      #   c.queues << @queue
      # end
    end
    subject{ @config }

    should have_accessors :name, :pid_file, :shutdown_timeout
    should have_accessors :worker_class, :worker_params, :num_workers
    should have_accessors :init_procs, :error_procs, :logger, :queues
    should have_accessors :verbose_logging
    should have_imeths :routes, :valid?, :validate!

    should "know its default attr values" do
      assert_equal 4, @config_class::DEFAULT_NUM_WORKERS
    end

    should "default its attrs" do
      assert_nil subject.name
      assert_nil subject.pid_file
      assert_nil subject.shutdown_timeout

      assert_equal DefaultWorker, subject.worker_class

      assert_nil subject.worker_params

      exp = @config_class::DEFAULT_NUM_WORKERS
      assert_equal exp, subject.num_workers

      assert_equal [], subject.init_procs
      assert_equal [], subject.error_procs

      assert_instance_of Qs::NullLogger, subject.logger

      assert_equal [],   subject.queues
      assert_equal true, subject.verbose_logging
    end

    should "know its routes" do
      exp = subject.queues.map(&:routes).flatten
      assert_equal exp, subject.routes
    end

    should "not be valid until validate! has been run" do
      assert_false subject.valid?

      subject.name = Factory.string
      subject.queues << @queue

      subject.validate!
      assert_true subject.valid?
    end

    should "complain if validating and its name is nil or it has no queues" do
      subject.name = nil
      subject.queues << @queue
      assert_raises(InvalidError){ subject.validate! }

      subject.name = Factory.string
      subject.queues.clear
      assert_raises(InvalidError){ subject.validate! }
    end

    should "complain if validating and its worker class isn't a Worker" do
      subject.name = Factory.string
      subject.queues << @queue

      subject.worker_class = Module.new
      assert_raises(InvalidError){ subject.validate! }

      subject.worker_class = Class.new
      assert_raises(InvalidError){ subject.validate! }
    end

  end

  class ValidationTests < ConfigTests
    desc "when successfully validated"
    setup do
      @config = Config.new.tap do |c|
        c.name = Factory.string
        c.queues << @queue
      end

      @initialized = false
      @config.init_procs << proc{ @initialized = true }

      @other_initialized = false
      @config.init_procs << proc{ @other_initialized = true }
    end

    should "call its init procs" do
      assert_equal false, @initialized
      assert_equal false, @other_initialized

      subject.validate!

      assert_equal true, @initialized
      assert_equal true, @other_initialized
    end

    should "validate its routes" do
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

    should "only be able to be validated once" do
      called = 0
      subject.init_procs << proc{ called += 1 }
      subject.validate!
      assert_equal 1, called
      subject.validate!
      assert_equal 1, called
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

  class StateTests < UnitTests
    desc "State"
    setup do
      @state = State.new
    end
    subject{ @state }

    should have_imeths :run?, :stop?, :halt?

    should "be a dat-worker-pool locked object" do
      assert State < DatWorkerPool::LockedObject
    end

    should "know if its in the run state" do
      assert_false subject.run?
      subject.set :run
      assert_true subject.run?
    end

    should "know if its in the stop state" do
      assert_false subject.stop?
      subject.set :stop
      assert_true subject.stop?
    end

    should "know if its in the halt state" do
      assert_false subject.halt?
      subject.set :halt
      assert_true subject.halt?
    end

  end

  TestHandler = Class.new

end
