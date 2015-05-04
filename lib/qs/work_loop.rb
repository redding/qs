require 'dat-worker-pool'
require 'qs/client'
require 'qs/io_pipe'

module Qs

  class WorkLoop

    # * Use 0 for the brpop timeout which means block indefinitely.

    SIGNAL = '.'.freeze

    def initialize(daemon)
      @daemon = daemon
      @logger = @daemon.logger

      @client = QsClient.new(@daemon.redis_config)
      @stack  = MiddlewareStack.new(@daemon.middlewares)

      @signals_redis_key = @daemon.signals_redis_key
      @queue_redis_keys  = @daemon.queues.map(&:redis_key)

      @worker_available_io = IOPipe.new
      @worker_pool = DatWorkerPool.new(
        daemon.min_workers,
        daemon.max_workers
      ){ |redis_item| process(redis_item) }
      @worker_pool.on_worker_error{ |*args| handler_worker_exception(*args) }
      @worker_pool.on_worker_sleep{ signal_worker_available }

      @switch = Switch.new(:stop)
      @thread = nil
    end

    def start
      return if self.running?
      @switch.set :start
      @thread ||= Thread.new{ run }
    end

    def stop
      return if !self.running?

    end

    def halt
      return if !self.running?

    end

    def running?
      !!(@thread && @thread.alive?)
    end

    private

    def run
      log :debug, "Starting work loop"
      setup
      fetch while @switch.start?
    rescue StandardError => exception
      @switch.set :stop
      log :error, "Error occurred while running the daemon, exiting"
      log :error, "#{exception.class}: #{exception.message}"
      log :error, exception.backtrace.join("\n")
    ensure
      log :debug, "Stopping work loop"
      teardown
      log :debug, "Stopped work loop"
    end

    # clear any signals that are already on the signals redis list
    def setup
      @client.clear(@signals_redis_key)
      @worker_available_io.setup
      @worker_pool.start
    end

    # * Shuffle the queue redis keys to avoid queue starvation. Redis will
    #   pull jobs off queues in the order they are passed to the command, by
    #   shuffling we ensure they are randomly ordered so every queue should
    #   get a chance.
    # * Rescue runtime errors so the daemon thread doesn't fail if redis is
    #   temporarily down. Sleep for a second to keep the thread from thrashing
    #   by repeatedly erroring if redis is down.
    def fetch
      if !@worker_pool.worker_available? && @switch.start?
        @worker_available_io.wait
        @worker_available_io.read # read off signal that worker is available
      end
      return if !@switch.start?

      begin
        args = [@signals_redis_key, @queue_redis_keys.shuffle, DEQUEUE_TIMEOUT]
        redis_key, serialized_payload = @client.block_dequeue(*args)
        if redis_key != @signals_redis_key
          @worker_pool.add_work(RedisItem.new(redis_key, serialized_payload))
        end
      rescue RuntimeError => exception
        log :error, "Error dequeueing #{exception.message.inspect}"
        log :error, exception.backtrace.join("\n")
        sleep DEQUEUE_ERROR_TIMEOUT
      end
    end

    def teardown
      log :info, "Shutting down"
      timeout = @switch.stop? ? @shutdown_timeout : HALT_TIMEOUT
      if timeout
        log :info, "Waiting up to #{timeout} second(s) for work to finish"
      else
        log :info, "Waiting for work to finish"
      end
      @worker_pool.shutdown(timeout)

      log :info, "Requeueing #{@worker_pool.work_items.size} job(s)"
      @worker_pool.work_items.each do |ri|
        @client.prepend(ri.queue_redis_key, ri.serialized_payload)
      end

      @worker_pool.clear
      @worker_available_io.teardown
      @thread = nil
    end

  end

end

# def initialize
#   @client = QsClient.new(Qs.redis_config.merge({
#     :timeout => 1,
#     :size    => self.daemon_data.max_workers + 1
#   }))

#   @signals_redis_key = "signals:#{@daemon_data.name}-" \
#                        "#{Socket.gethostname}-#{::Process.pid}"
# end

# def stop
#   return unless self.running?
#   @signal.set :stop
#   wakeup_work_loop_thread
#   wait_for_shutdown if wait
# end

# def halt(wait = false)
#   return unless self.running?
#   @signal.set :halt
#   wakeup_work_loop_thread
#   wait_for_shutdown if wait
# end

# def process(redis_item)
#   Qs::PayloadHandler.new(self.daemon_data, redis_item).run
# end

# def wait_for_shutdown
#   @work_loop_thread.join if @work_loop_thread
# end

# def wakeup_work_loop_thread
#   @client.append(self.signals_redis_key, SIGNAL)
#   @worker_available_io.write(SIGNAL)
# end

# # * This only catches errors that happen outside of running the payload
# #   handler. The only known use-case for this is dat worker pools
# #   hard-shutdown errors.
# # * If there isn't a redis item (this can happen when an idle worker is
# #   being forced to exit) then we don't need to do anything.
# # * If we never started processing the redis item, its safe to requeue it.
# #   Otherwise it happened while processing so the payload handler caught
# #   it or it happened after the payload handler which we don't care about.
# def handle_worker_exception(exception, redis_item)
#   return if redis_item.nil?
#   if !redis_item.started
#     log "Worker error, requeueing job because it hasn't started", :error
#     @client.prepend(redis_item.queue_redis_key, redis_item.serialized_payload)
#   else
#     log "Worker error after job was processed, ignoring", :error
#   end
#   log "#{exception.class}: #{exception.message}", :error
#   log exception.backtrace.join("\n"), :error
# end

# def log(message, level = :info)
#   self.logger.send(level, "[Qs] #{message}")
# end

# class Signal
#   def initialize(value)
#     @value = value
#     @mutex = Mutex.new
#   end

#   def set(value)
#     @mutex.synchronize{ @value = value }
#   end

#   def start?
#     @mutex.synchronize{ @value == :start }
#   end

#   def stop?
#     @mutex.synchronize{ @value == :stop }
#   end

#   def halt?
#     @mutex.synchronize{ @value == :halt }
#   end
# end
