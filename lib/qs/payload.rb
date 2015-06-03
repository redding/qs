require 'qs'
require 'qs/event'
require 'qs/job'

module Qs

  module Payload

    PAYLOAD_TYPES = Hash.new{ |h, t| raise(InvalidError.new(t)) }.tap do |h|
      h[Job::PAYLOAD_TYPE]   = 'job'
      h[Event::PAYLOAD_TYPE] = 'event'
    end.freeze

    def self.deserialize(encoded_payload)
      payload_hash = Qs.decode(encoded_payload)
      self.send(PAYLOAD_TYPES[payload_hash['type']], payload_hash)
    end

    def self.serialize(message)
      Qs.encode(self.send("#{PAYLOAD_TYPES[message.payload_type]}_hash", message))
    end

    def self.job(payload_hash)
      Qs::Job.new(payload_hash['name'], {
        :params     => payload_hash['params'],
        :created_at => Timestamp.to_time(payload_hash['created_at'])
      })
    end

    def self.job_hash(job)
      self.message_hash(job, {
        'name'       => job.name.to_s,
        'created_at' => Timestamp.new(job.created_at)
      })
    end

    def self.event(payload_hash)
      Qs::Event.new(payload_hash['channel'], payload_hash['name'], {
        :params       => payload_hash['params'],
        :publisher    => payload_hash['publisher'],
        :published_at => Timestamp.to_time(payload_hash['published_at'])
      })
    end

    def self.event_hash(event)
      self.message_hash(event, {
        'channel'      => event.channel.to_s,
        'name'         => event.name.to_s,
        'publisher'    => event.publisher.to_s,
        'published_at' => Timestamp.new(event.published_at)
      })
    end

    # private

    def self.message_hash(message, hash)
      hash.tap do |h|
        h['type']   = message.payload_type.to_s
        h['params'] = StringifyParams.new(message.params)
      end
    end

    module StringifyParams
      def self.new(object)
        case(object)
        when Hash
          object.inject({}){ |h, (k, v)| h.merge(k.to_s => self.new(v)) }
        when Array
          object.map{ |item| self.new(item) }
        else
          object
        end
      end
    end

    module Timestamp
      def self.to_time(integer)
        Time.at(integer)
      end

      def self.new(time)
        time.to_i
      end
    end

    class InvalidError < ArgumentError
      def initialize(payload_type)
        super "unknown payload type #{payload_type.inspect}"
      end
    end

  end

end
