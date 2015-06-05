require 'qs/queue'
require 'qs/dispatch_job_handler'

module Qs

  module DispatcherQueue

    def self.new(options)
      options[:queue_class].new do
        name options[:queue_name]
        job options[:job_name], options[:job_handler_class_name]
      end
    end

    RunDispatchJob = Class.new{ include Qs::DispatchJobHandler }

  end

end
