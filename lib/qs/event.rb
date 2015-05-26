require 'qs/job'

module Qs

  class Event

    PAYLOAD_TYPE = 'event'

    def self.build(channel, name, params, options = nil)
      options ||= {}
      job_name   = Event::JobName.new(channel, name)
      job_params = {
        'event_channel' => channel,
        'event_name'    => name,
        'event_params'  => params
      }
      self.new(Qs::Job.new(job_name, job_params, {
        :type       => PAYLOAD_TYPE,
        :created_at => options[:published_at]
      }))
    end

    attr_reader :job

    def initialize(job)
      validate!(job)
      @job = job
    end

    def channel
      @job.params['event_channel']
    end

    def name
      @job.params['event_name']
    end

    def params
      @job.params['event_params']
    end

    def published_at
      @job.created_at
    end

    def inspect
      reference = '0x0%x' % (self.object_id << 1)
      "#<#{self.class}:#{reference} " \
      "@channel=#{self.channel.inspect} " \
      "@name=#{self.name.inspect} " \
      "@params=#{self.params.inspect} " \
      "@published_at=#{self.published_at.inspect}>"
    end

    def ==(other)
      if other.kind_of?(self.class)
        self.job == other.job
      else
        super
      end
    end

    private

    def validate!(job)
      problem = if job.params['event_channel'].to_s.empty?
        "The job doesn't have an event channel."
      elsif job.params['event_name'].to_s.empty?
        "The job doesn't have an event name."
      elsif !job.params['event_params'].kind_of?(::Hash)
        "The job's event params are not valid."
      end
      raise(BadEventError, problem) if problem
    end

    module JobName
      def self.new(event_channel, event_name)
        "#{event_channel}:#{event_name}"
      end
    end

  end

  BadEventError = Class.new(ArgumentError)

end
