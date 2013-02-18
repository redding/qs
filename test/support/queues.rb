require 'qs/queue'
require 'test/support/job_handlers'

module MyTestApp; end

class MyTestApp::TestQueue
  include Qs::Queue

  name 'test'
  job   :some_job,     "Some::Job"
  event :some, :event, "Some::Event"

end

class MyTestApp::NamespacedTestQueue
  include Qs::Queue

  name 'namespaced_test'
  job_handler_ns 'Some'
  event_handler_ns 'Some'

  job   :some_job,      "Job"
  job   :other_job,     "::Other::Job"
  event :some,  :event, "Event"
  event :other, :event, "::Other::Event"

  def enqueue(job)
    # just return the job it is supposed to enqueue since we are testing
    job
  end

end
