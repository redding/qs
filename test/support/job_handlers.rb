require 'qs/job_handler'

module MyTestApp; end
module MyTestApp::JobHandlers

  class TestJob
    include Qs::JobHandler
    attr_reader :init_was_called, :run_was_called

    def init!; @init_was_called = true; end
    def run!;  @run_was_called = true;  end
  end

  class CallbacksJob < TestJob

    attr_reader :before_init_called, :after_init_called
    attr_reader :before_run_called, :after_run_called
    attr_reader :on_failure_called

    def before_init; @before_init_called = true; end
    def after_init;  @after_init_called  = true; end

    def before_run; @before_run_called = true; end
    def after_run;  @after_run_called  = true; end

    def on_failure(exception)
      @on_failure_called = exception
    end
  end

  class FailingInitJob < CallbacksJob
    def init!; raise 'to call on_failure during init'; end
  end

  class FailingRunJob < CallbacksJob
    def run!; raise 'to call on_failure during run'; end
  end

  class FailingCallbackJob < CallbacksJob
    def before_run; raise 'to call on_failure during before_run'; end
  end

end

