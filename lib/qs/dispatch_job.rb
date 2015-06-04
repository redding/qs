require 'qs'
require 'qs/event'
require 'qs/job'

module Qs

  class DispatchJob < Qs::Job

    def self.event(job)
      Qs::Event.new(job.params['event_channel'], job.params['event_name'], {
        :params       => job.params['event_params'],
        :publisher    => job.params['event_publisher'],
        :published_at => job.created_at
      })
    end

    def initialize(event_channel, event_name, options = nil)
      options ||= {}
      event_params    = options.delete(:event_params)    || {}
      event_publisher = options.delete(:event_publisher) || Qs.event_publisher
      options[:params] = {
        'event_channel'   => event_channel,
        'event_name'      => event_name,
        'event_params'    => event_params,
        'event_publisher' => event_publisher
      }
      super(Qs.dispatcher_job_name, options)
    end

    def event
      @event ||= self.class.event(self)
    end

  end

end
