require 'much-plugin'

module Qs

  module MessageHandler
    include MuchPlugin

    plugin_included do
      extend ClassMethods
      include InstanceMethods
    end

    module InstanceMethods

      def initialize(runner)
        @qs_runner = runner
      end

      def qs_init
        self.qs_run_callback 'before_init'
        self.init!
        self.qs_run_callback 'after_init'
      end

      def init!
      end

      def qs_run
        self.qs_run_callback 'before_run'
        self.run!
        self.qs_run_callback 'after_run'
      end

      def run!
      end

      def qs_run_callback(callback)
        (self.class.send("#{callback}_callbacks") || []).each do |callback|
          self.instance_eval(&callback)
        end
      end

      def ==(other_handler)
        self.class == other_handler.class
      end

      private

      # Helpers

      def logger; @qs_runner.logger; end
      def params; @qs_runner.params; end
      def halt;   @qs_runner.halt;   end

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
