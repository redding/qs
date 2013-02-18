require 'qs'
require 'qs/job'

module Qs

  module JobHandler

    attr_reader :name, :args, :enqueued_job

    def initialize(args, enqueued_job)
      @name, @args, @enqueued_job = self.class.to_s, Args.new(args), enqueued_job
    end

    def init; run_action('init') { self.init! }; end
    def run;  run_action('run')  { self.run!  }; end

    # Hooks - override to put in handler-specific logic

    def init!; end
    def run!; raise NotImplementedError; end

    # Callbacks - override as needed
    # TODO: make class level chained blocks (after initial beta)

    def before_init; end
    def after_init; end
    def before_run; end
    def after_run; end
    def on_failure(*args); end

    # Settings - override for handler-specific values

    def timeout; Qs.config.timeout; end
    def logger;  Qs.config.logger;  end

    private

    def run_action(action)
      begin
        run_callback "before_#{action}"
        yield
        run_callback "after_#{action}"
      rescue Exception => exception
        run_callback 'on_failure', exception
        raise(exception)
      end
    end

    def run_callback(meth, *args)
      self.send(meth.to_s, *args)
    end

    # utility classes

    # the Args class composes an args hash.  It converts all keys to strings
    # and overrides the to_s to use the ArgsPrinter.

    class Args
      def initialize(args=nil)
        @hash = {}
        build_from(args || {})
      end

      def to_s; ArgsPrinter.new(@hash).to_s; end
      def to_hash; @hash.dup; end

      alias_method :hash, :to_hash # DEPRECATED - for backwards compatability

      def [](key); @hash[key.to_s]; end
      def []=(key, value); @hash[key.to_s] = value; end

      def keys;  @hash.keys;  end
      def clear; @hash.clear; end

      private

      def build_from(other_hash)
        other_hash.each{|k, v| self[k] = v }
      end
    end

    # The ArgsPrinter handles recursively truncating long values for nicer
    # output when logging etc.

    class ArgsPrinter
      MAX_LENGTH = 25

      def initialize(object)
        @object, @string = object, process(object)
      end

      def to_s; @string; end

      protected

      def process(object)
        case(object)
        when Array
          "[ #{object.map{|item| process(item) }.join(', ')} ]"
        when Hash
          k_v = object.map{|(k, v)| "#{k.inspect} => #{process(v)}" }
          "{ #{k_v.sort.join(', ')} }"
        when Integer, Symbol, Float
          truncate(object.inspect)
        else
          truncate(object).inspect
        end
      end

      def truncate(o)
        (os = o.to_s).size <= MAX_LENGTH ? os : "#{os[0, MAX_LENGTH]}..."
      end

    end

  end

end
