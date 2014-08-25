require 'logger'

module Qs

  module TmpDaemon

    def self.included(klass)
      klass.class_eval do
        extend ClassMethods
        include InstanceMethods
      end
    end

    module InstanceMethods

      def name
        self.class.name
      end

      def logger
        self.class.logger
      end

      def pid_file
        self.class.pid_file
      end

    end

    module ClassMethods

      def name(value = nil)
        @name = value unless value.nil?
        @name
      end

      def logger(value = nil)
        @logger = value unless value.nil?
        @logger || ::Logger.new('/dev/null')
      end

      def pid_file(value = nil)
        @pid_file = value unless value.nil?
        @pid_file
      end

    end

  end

end
