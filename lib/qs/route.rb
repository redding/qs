module Qs

  class Route

    attr_reader :name, :handler_class_name, :handler_class

    def initialize(name, handler_class_name)
      @name = name.to_s
      @handler_class_name = handler_class_name
      @handler_class = nil
    end

    def validate!
      @handler_class = constantize_handler_class(@handler_class_name)
    end

    def run
      # TODO
    end

    private

    def constantize_handler_class(handler_class_name)
      constantize(handler_class_name).tap do |handler_class|
        raise(NoHandlerClassError.new(handler_class_name)) if !handler_class
      end
    end

    def constantize(class_name)
      names = class_name.to_s.split('::').reject{ |name| name.empty? }
      klass = names.inject(Object){ |constant, name| constant.const_get(name) }
      klass == Object ? false : klass
    rescue NameError
      false
    end

  end

  class NoHandlerClassError < RuntimeError
    def initialize(handler_class_name)
      super "Qs couldn't find the handler '#{handler_class_name}'" \
            " - it doesn't exist or hasn't been required in yet."
    end
  end

end
