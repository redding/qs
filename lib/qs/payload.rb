require 'oj'

module Qs

  module Payload

    def self.encode(payload)
      Oj.dump(payload, :mode => :strict)
    end

    def self.decode(payload)
      Oj.load(payload, :mode => :strict)
    end

  end

end
