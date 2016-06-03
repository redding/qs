module Qs

  class DaemonData

    # The daemon uses this to "compile" the common configuration data used
    # by the daemon instances, error handlers and routes. The goal here is
    # to provide these with a simplified interface with the minimal data needed
    # and to decouple the configuration from each thing that needs its data.

    attr_reader :name, :pid_file, :shutdown_timeout
    attr_reader :worker_class, :worker_params, :num_workers
    attr_reader :error_procs, :logger, :queue_redis_keys
    attr_reader :verbose_logging
    attr_reader :debug, :dwp_logger, :routes, :process_label

    def initialize(args = nil)
      args ||= {}
      @name     = args[:name]
      @pid_file = args[:pid_file]

      @shutdown_timeout = args[:shutdown_timeout]

      @worker_class     = args[:worker_class]
      @worker_params    = args[:worker_params] || {}
      @num_workers      = args[:num_workers]
      @error_procs      = args[:error_procs] || []
      @logger           = args[:logger]
      @queue_redis_keys = (args[:queues] || []).map(&:redis_key)

      @verbose_logging = !!args[:verbose_logging]

      @debug      = !ENV['QS_DEBUG'].to_s.empty?
      @dwp_logger = @logger if @debug
      @routes     = build_routes(args[:routes] || [])

      @process_label = !(v = ENV['QS_PROCESS_LABEL'].to_s).empty? ? v : @name
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
