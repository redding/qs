require 'qs/runner'

module Qs

  class QsRunner < Runner

    def run
      run_callbacks self.handler_class.before_callbacks
      self.handler.init
      self.handler.run
      run_callbacks self.handler_class.after_callbacks
    end

    private

    def run_callbacks(callbacks)
      callbacks.each{ |proc| self.handler.instance_eval(&proc) }
    end

  end

end
