require 'qs'
require 'qs/job'

module Qs

  module Payload

    def self.deserialize(encoded_payload)
      self.job(Qs.decode(encoded_payload))
    end

    def self.job(payload_hash)
      Qs::Job.new(payload_hash['name'], payload_hash['params'], {
        :type       => payload_hash['type'],
        :created_at => Time.at(payload_hash['created_at'].to_i)
      })
    end

    def self.serialize(message)
      Qs.encode(self.job_hash(message))
    end

    def self.job_hash(job)
      { 'type'       => job.payload_type.to_s,
        'name'       => job.name.to_s,
        'params'     => StringifyParams.new(job.params),
        'created_at' => job.created_at.to_i
      }
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

  end

end
