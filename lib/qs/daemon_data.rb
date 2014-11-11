module Qs

  class DaemonData

    # The daemon uses this to "compile" its configuration for speed. NsOptions
    # is relatively slow everytime an option is read. To avoid this, we read the
    # options one time here and memoize their values. This way, we don't pay the
    # NsOptions overhead when reading them while handling a job.

    attr_reader :name
    attr_reader :pid_file
    attr_reader :min_workers, :max_workers
    attr_reader :logger, :verbose_logging
    attr_reader :shutdown_timeout
    attr_reader :error_procs
    attr_reader :queue_redis_keys, :routes

    def initialize(args = nil)
      args ||= {}
      @name = args[:name]
      @pid_file = args[:pid_file]
      @min_workers = args[:min_workers]
      @max_workers = args[:max_workers]
      @logger = args[:logger]
      @verbose_logging = !!args[:verbose_logging]
      @shutdown_timeout = args[:shutdown_timeout]
      @error_procs = args[:error_procs] || []
      @queue_redis_keys = args[:queue_redis_keys] || []
      @routes = build_routes(args[:routes] || [])
    end

    def route_for(name)
      @routes[name] || raise(NotFoundError, "no service named '#{name}'")
    end

    private

    def build_routes(routes)
      routes.inject({}){ |h, route| h.merge(route.name => route) }
    end

  end

  NotFoundError = Class.new(RuntimeError)

end
