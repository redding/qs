module Qs

  class Message

    attr_reader :payload_type, :params

    def initialize(payload_type, params = nil)
      @payload_type = payload_type.to_s
      @params       = params || {}
    end

    def route_id
      @route_id ||= RouteId.new(self.payload_type, self.route_name)
    end

    def route_name
      raise NotImplementedError
    end

    module RouteId
      def self.new(payload_type, route_name)
        "#{payload_type}|#{route_name}"
      end
    end

  end

end
