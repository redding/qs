module Qs

  module TmpDaemon

    def self.included(klass)
      klass.class_eval do
        extend ClassMethods
        include InstanceMethods
      end
    end

    module InstanceMethods

      def pid_file
        self.class.pid_file
      end

    end

    module ClassMethods

      def pid_file(value = nil)
        @pid_file = value unless value.nil?
        @pid_file
      end

    end

  end

end
