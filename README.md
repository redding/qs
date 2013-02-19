# Qs

Setup message queues.  Run jobs and events.  Profit.

## Usage

TODO: fill out code snippets with details

Define a queue:

```ruby
# in config/queues.rb

class MyQueue
  include Qs::Queue

  name 'main'

  job :do_something,  "MyJobs::DoSomething"

end
```

Define a handler for `DoSomething`:

```ruby
module MyJobs
  class DoSomething
    include Qs::JobHandler

    def run!
      # do something
    end

  end
end
```

Submit jobs to the queue with a payload:

```ruby
MyQueue.add :do_something, {:some => 'payload'}
```

Run a worker to handle jobs on the queue:

```
$ qs start main
```

Qs is a framework for running message queues.  There are APIs for both submitting bg jobs and publishing and subscribing to event jobs.

TODO: code snippets for both adding jobs and publishing events

# Redis

TODO: add a note about redis usage and connecting

## Installation

Add this line to your application's Gemfile:

    gem 'qs'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install qs

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Added some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
