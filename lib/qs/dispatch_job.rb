require 'qs'
require 'qs/event'
require 'qs/job'

module Qs

  class DispatchJob < Qs::Job

    def initialize(event_channel, event_name, event_params, options = nil)
      params = {
        'event_channel' => event_channel,
        'event_name'    => event_name,
        'event_params'  => event_params
      }
      super(Qs.dispatcher_job_name, params, options)
    end

    def event
      @event ||= Qs::Event.new(
        params['event_channel'],
        params['event_name'],
        params['event_params'],
        { :published_at => self.created_at }
      )
    end

  end

end
