module Qs

  class DaemonData

    # The daemon uses this to "compile" its configuration for speed. NsOptions
    # is relatively slow everytime an option is read. To avoid this, we read the
    # options one time here and memoize their values. This way, we don't pay the
    # NsOptions overhead when reading them while handling a message.

    attr_reader :name, :process_label
    attr_reader :pid_file
    attr_reader :worker_class, :worker_params
    attr_reader :num_workers
    attr_reader :logger, :verbose_logging
    attr_reader :shutdown_timeout
    attr_reader :error_procs
    attr_reader :queue_redis_keys, :routes

    def initialize(args = nil)
      args ||= {}
      @name             = args[:name]
      @process_label    = !(v = ENV['QS_PROCESS_LABEL'].to_s).empty? ? v : args[:name]
      @pid_file         = args[:pid_file]
      @worker_class     = args[:worker_class]
      @worker_params    = args[:worker_params] || {}
      @num_workers      = args[:num_workers]
      @logger           = args[:logger]
      @verbose_logging  = !!args[:verbose_logging]
      @shutdown_timeout = args[:shutdown_timeout]
      @error_procs      = args[:error_procs] || []
      @queue_redis_keys = args[:queue_redis_keys] || []
      @routes           = build_routes(args[:routes] || [])
    end

    def route_for(route_id)
      @routes[route_id] || raise(NotFoundError, "unknown message '#{route_id}'")
    end

    private

    def build_routes(routes)
      routes.inject({}){ |h, route| h.merge(route.id => route) }
    end

  end

  NotFoundError = Class.new(RuntimeError)

end
