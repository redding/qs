require 'qs/job'

module Qs

  class Event

    def self.from_job(job)
      handler_args = job.handler_args || {}
      channel = handler_args['channel'] || ''
      name    = handler_args['event']   || ''
      args    = handler_args['args']    || {}

      Event.new(channel, name, args).tap do |event|
        event.publisher    = handler_args['publisher'] || ''
        event.published_at = Time.at(handler_args['published_at'].to_i)
      end
    end

    attr_reader   :channel, :name, :args
    attr_accessor :publisher, :published_at

    def initialize(channel, name, args=nil)
      @channel, @name, @args = channel.to_s, name.to_s, (args || {})
      @publisher = ''
      @published_at = nil
    end

    def key
      "#{@channel}:#{@name}"
    end

    def validate!
      if (@channel || '').empty? && (@name || '').empty?
        raise ArgumentError, "An event requires both a channel and a name:"\
                             " channel=#{self.channel.inspect}"\
                             " name=#{self.name.inspect}"
      end

      if @published_at.nil?
        raise ArgumentError, "No published_at time has been specified."
      end
    end

    def published?
      !!@published_at
    end

    def to_job(dest=nil)
      # TODO dest ||= I::Events.distributor
      queue_class   = dest.nil? ? 'QueueClass'   : dest.queue_class
      handler_class = dest.nil? ? 'HandlerClass' : dest.handler_class
      Qs::Job.new(queue_class, handler_class, self.to_job_args)
    end

    def to_job_args
      { 'channel'      => @channel,
        'event'        => @name,
        'args'         => @args,
        'publisher'    => @publisher,
        'published_at' => @published_at.to_i
      }
    end

    def ==(other_event)
      self.channel   == other_event.channel &&
      self.name      == other_event.name    &&
      self.args      == other_event.args
    end

  end

end
