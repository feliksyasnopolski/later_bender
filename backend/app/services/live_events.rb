require "thread"

class LiveEvents
  Event = Data.define(:type, :ref, :attributes) do
    def json
      { "type" => type, "ref" => ref }.merge(attributes).to_json
    end
  end

  class << self
    def subscribe(user_id)
      queue = Queue.new
      mutex.synchronize { subscribers[user_id] << queue }
      queue
    end

    def unsubscribe(user_id, queue)
      mutex.synchronize { subscribers[user_id]&.delete(queue) }
    end

    def publish(user:, type:, ref:, **attributes)
      event = Event.new(type, ref, attributes)
      queues = mutex.synchronize { subscribers[user.id].dup }
      queues.each { |queue| queue << event }
      event
    end

    private

    def mutex = @mutex ||= Mutex.new
    def subscribers = @subscribers ||= Hash.new { |hash, key| hash[key] = [] }
  end
end
