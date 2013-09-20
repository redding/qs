module Qs

  class Job

    def self.parse(job_string)
      self.new({}) # TODO
    end

    attr_reader :name, :type, :params

    def initialize(job_hash)
      # TODO
      @name   = 'test_job'
      @type   = 'job'
      @params = { 'some' => 'param' }
    end

  end

end
