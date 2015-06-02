module Qs

  module MessageHandler

    def self.included(klass)
      klass.class_eval do
        extend ClassMethods
        include InstanceMethods
      end
    end

    module InstanceMethods

      def initialize(runner)
        @qs_runner = runner
      end

      def init
        run_callback 'before_init'
        self.init!
        run_callback 'after_init'
      end

      def init!
      end

      def run
        run_callback 'before_run'
        self.run!
        run_callback 'after_run'
      end

      def run!
        raise NotImplementedError
      end

      private

      # Helpers

      def params; @qs_runner.params; end
      def logger; @qs_runner.logger; end

      def run_callback(callback)
        (self.class.send("#{callback}_callbacks") || []).each do |callback|
          self.instance_eval(&callback)
        end
      end

    end

    module ClassMethods

      def timeout(value = nil)
        @timeout = value.to_f if value
        @timeout
      end

      def before_callbacks;      @before_callbacks      ||= []; end
      def after_callbacks;       @after_callbacks       ||= []; end
      def before_init_callbacks; @before_init_callbacks ||= []; end
      def after_init_callbacks;  @after_init_callbacks  ||= []; end
      def before_run_callbacks;  @before_run_callbacks  ||= []; end
      def after_run_callbacks;   @after_run_callbacks   ||= []; end

      def before(&block);      self.before_callbacks      << block; end
      def after(&block);       self.after_callbacks       << block; end
      def before_init(&block); self.before_init_callbacks << block; end
      def after_init(&block);  self.after_init_callbacks  << block; end
      def before_run(&block);  self.before_run_callbacks  << block; end
      def after_run(&block);   self.after_run_callbacks   << block; end

      def prepend_before(&block);      self.before_callbacks.unshift(block);      end
      def prepend_after(&block);       self.after_callbacks.unshift(block);       end
      def prepend_before_init(&block); self.before_init_callbacks.unshift(block); end
      def prepend_after_init(&block);  self.after_init_callbacks.unshift(block);  end
      def prepend_before_run(&block);  self.before_run_callbacks.unshift(block);  end
      def prepend_after_run(&block);   self.after_run_callbacks.unshift(block);   end

    end

  end

end
