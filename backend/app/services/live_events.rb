require "json"
require "redis"
require "thread"

class LiveEvents
  CHANNEL = "later-bender:live-events"

  Event = Data.define(:type, :ref, :attributes) do
    def json
      { "type" => type, "ref" => ref }.merge(attributes).to_json
    end
  end

  class << self
    def subscribe(user_id)
      queue = Queue.new
      mutex.synchronize do
        subscribers[user_id] << queue
        start_subscriber_locked if redis_url && subscriber_thread.nil?
      end
      queue
    end

    def unsubscribe(user_id, queue)
      thread = connection = nil
      mutex.synchronize do
        subscribers[user_id]&.delete(queue)
        subscribers.delete(user_id) if subscribers[user_id]&.empty?
        if subscribers.empty? && subscriber_thread
          @subscriber_stop = true
          thread = @subscriber_thread
          connection = @subscriber_connection
          @subscriber_thread = nil
          @subscriber_connection = nil
        end
      end
      stop_subscriber(thread, connection)
    end

    def publish(user:, type:, ref:, **attributes)
      event = Event.new(type, ref, attributes)
      if redis_url
        redis.publish(CHANNEL, JSON.generate("user_id" => user.id, "event" => JSON.parse(event.json)))
      else
        deliver(user.id, event)
      end
    rescue Redis::BaseError
      # Redis is only an invalidation hint. A failed publish must not fail the
      # canonical mutation, and local clients can still converge immediately.
      deliver(user.id, event)
      event
    end

    def shutdown!
      thread = connection = nil
      mutex.synchronize do
        next unless subscriber_thread

        @subscriber_stop = true
        thread = @subscriber_thread
        connection = @subscriber_connection
        @subscriber_thread = nil
        @subscriber_connection = nil
      end
      stop_subscriber(thread, connection)
    end

    private

    def mutex = @mutex ||= Mutex.new
    def subscribers = @subscribers ||= Hash.new { |hash, key| hash[key] = [] }
    def redis_url = ENV["REDIS_URL"].presence
    def redis = Redis.new(url: redis_url, connect_timeout: 1, timeout: 1)

    def deliver(user_id, event)
      queues = mutex.synchronize { subscribers[user_id].dup }
      queues.each { |queue| queue << event }
    end

    def start_subscriber_locked
      @subscriber_stop = false
      @subscriber_thread = Thread.new do
        Thread.current.report_on_exception = false
        subscriber_loop
      end
    end

    def stop_subscriber(thread, connection)
      return unless thread

      thread.kill if thread.alive?
      connection&.close
      thread.join(1)
    end

    def subscriber_thread = @subscriber_thread

    def subscriber_loop
      loop do
        break if stopping?

        connection = Redis.new(url: redis_url, connect_timeout: 1)
        mutex.synchronize { @subscriber_connection = connection }
        connection.subscribe(CHANNEL) do |on|
          on.message do |_channel, payload|
            parsed = JSON.parse(payload)
            deliver(parsed.fetch("user_id"), event_from_json(parsed.fetch("event")))
          rescue JSON::ParserError, KeyError, TypeError
            # Ignore malformed ephemeral messages; HTTP remains canonical.
          end
        end
      rescue Redis::BaseError, IOError, SystemCallError
        sleep 0.25 unless stopping?
      ensure
        connection&.close
        mutex.synchronize { @subscriber_connection = nil if @subscriber_connection.equal?(connection) }
      end
    end

    def event_from_json(payload)
      Event.new(payload.fetch("type"), payload.fetch("ref"), payload.except("type", "ref"))
    end

    def stopping?
      mutex.synchronize { @subscriber_stop }
    end
  end
end
