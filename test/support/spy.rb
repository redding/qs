class Spy

  def initialize(subject)
    @subject = subject
    @subject_metaclass = (class << @subject; self; end)
    @metaclass         = (class << self; self; end)
    @tracked_methods          = {}
    @tracked_instance_methods = {}
  end

  def method(name)
    @tracked_methods[name.to_s]
  end

  def instance_method(name)
    @tracked_instance_methods[name.to_s]
  end

  def track(name)
    @tracked_methods[name.to_s] = Method.new(name).tap do |m|
      m.add_to(@subject_metaclass)
    end
    true
  end

  def ignore(name)
    @tracked_methods.delete(name.to_s).tap do |m|
      m.remove_from(@subject_metaclass)
    end
    true
  end

  def track_on_instance(name)
    @tracked_instance_methods[name.to_s] = Method.new(name).tap do |m|
      m.add_to(@subject)
    end
    true
  end

  def ignore_on_instance(name)
    @tracked_instance_methods.delete(name.to_s).tap do |m|
      m.remove_from(@subject)
    end
    true
  end

  class Method
    attr_reader :name, :original_method_name, :calls

    def initialize(name)
      @name = name
      @original_method_name = "__spy_original_#{@name}__"
      @calls = []
    end

    def called(*args, &block)
      @calls << MethodCall.new(@name, args, block)
    end

    def add_to(object)
      method = self
      object.class_eval do

        alias_method method.original_method_name, method.name

        define_method(method.name) do |*args, &block|
          method.called(*args, &block)
          # TODO - allow passing through, on/off
        end

      end
    end

    def remove_from(object)
      method = self
      object.class_eval do

        remove_method method.name

        alias_method method.name, method.original_method_name

      end
    end
  end

  MethodCall = Struct.new(:name, :args, :block)

end
