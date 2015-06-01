require 'qs/message'

module Qs

  class Job < Message

    PAYLOAD_TYPE = 'job'

    attr_reader :name, :created_at

    def initialize(name, params, options = nil)
      validate!(name, params)
      options ||= {}
      @name       = name
      @created_at = options[:created_at] || Time.now
      super(PAYLOAD_TYPE, params)
    end

    def route_name
      self.name
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
        self.payload_type == other.payload_type &&
        self.name         == other.name         &&
        self.params       == other.params       &&
        self.created_at   == other.created_at
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

  end

  BadJobError = Class.new(ArgumentError)

end
