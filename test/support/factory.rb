require 'assert/factory'

module Factory
  extend Assert::Factory

  def self.exception(klass = nil, message = nil)
    klass ||= StandardError
    message ||= Factory.text
    exception = nil
    begin; raise(klass, message); rescue StandardError => exception; end
    exception
  end

end
