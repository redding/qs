module Qs

  class Job

    def self.parse(payload)
      created_at = Time.at(payload['created_at'].to_i)
      self.new(payload['name'], payload['params'], created_at)
    end

    attr_reader :name, :params, :created_at

    def initialize(name, params, created_at = nil)
      validate!(name, params)
      @name       = name
      @params     = params
      @created_at = created_at || Time.now
    end

    def to_payload
      { 'name'       => self.name.to_s,
        'params'     => StringifyParams.new(self.params),
        'created_at' => self.created_at.to_i
      }
    end

    def inspect
      reference = '0x0%x' % (self.object_id << 1)
      "#<#{self.class}:#{reference} " \
      "@name=#{self.name.inspect} " \
      "@params=#{self.params.inspect} " \
      "@created_at=#{self.created_at.inspect}>"
    end

    def ==(other)
      if other.kind_of?(self.class)
        self.to_payload == other.to_payload
      else
        super
      end
    end

    private

    def validate!(name, params)
      problem = if name.to_s.empty?
        "The job doesn't have a name."
      elsif !params.kind_of?(::Hash)
        "The job's params are not valid."
      end
      raise(BadJobError, problem) if problem
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

  BadJobError = Class.new(ArgumentError)

end
