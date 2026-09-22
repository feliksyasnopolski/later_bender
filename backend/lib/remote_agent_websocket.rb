require "json"
require "securerandom"
require "websocket/driver"

class RemoteAgentWebsocket
  PATH = "/api/remote-agent/stream"
  POLL_INTERVAL = 0.5
  HEARTBEAT_INTERVAL = 10
  HEARTBEAT_DEADLINE = 5

  def self.middleware(app)
    new(app)
  end

  def initialize(app)
    @app = app
  end

  def call(env)
    return @app.call(env) unless env["PATH_INFO"] == PATH && WebSocket::Driver.websocket?(env)
    token = env["HTTP_AUTHORIZATION"].to_s.delete_prefix("Bearer ")
    session = RemoteAgentSession.authenticate(token)
    return [ 401, { "content-type" => "application/json", "content-length" => "0" }, [] ] unless session

    RemoteAgentWebsocket::Connection.new(env, session).run
    [ -1, {}, [] ]
  rescue StandardError => e
    Rails.logger.warn("Remote Agent WSS connection failed: #{e.class}: #{e.message}")
    [ 401, { "content-type" => "application/json", "content-length" => "0" }, [] ]
  end

  class Connection
    attr_reader :env, :url

    def initialize(env, session)
      @env = env
      @session = session
      scheme = env["HTTPS"] == "on" || env["HTTP_X_FORWARDED_PROTO"] == "https" ? "wss" : "ws"
      @url = "#{scheme}://#{env['HTTP_HOST']}#{env['REQUEST_URI']}"
      @write_mutex = Mutex.new
      @driver_mutex = Mutex.new
      @closed = false
      @last_pong = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @driver = WebSocket::Driver.rack(self, protocols: [ "later-bender-agent-v1" ])
      @driver.on(:open) { send_json("type" => "ready", "heartbeat_interval_seconds" => HEARTBEAT_INTERVAL) }
      @driver.on(:message) { |event| receive(event.data) }
      @driver.on(:close) { close! }
      @driver.on(:error) { |event| Rails.logger.info("Remote Agent WSS protocol error: #{event.message}") }
    end

    def run
      @env["rack.hijack"].call
      @io = @env["rack.hijack_io"]
      @driver.start
      @reader = Thread.new do
        loop do
          bytes = @io.readpartial(16 * 1024)
          @driver.parse(bytes)
        end
      rescue EOFError, IOError, SystemCallError
        close!
      rescue StandardError => e
        Rails.logger.warn("Remote Agent WSS reader failed: #{e.class}: #{e.message}")
        close!
      end
      @writer = Thread.new { write_loop }
      @reader.join
      close!
      @writer.join
    end

    def write(value)
      @write_mutex.synchronize { @io.write(value) unless @closed }
    rescue IOError, SystemCallError
      close!
    end

    private

    def write_loop
      last_heartbeat = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      loop do
        break if @closed
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if now - @last_pong > HEARTBEAT_INTERVAL + HEARTBEAT_DEADLINE
          close!
          break
        end
        if now - last_heartbeat >= HEARTBEAT_INTERVAL
          @ping_id = SecureRandom.hex(8)
          @ping_sent_at = now
          send_json("type" => "ping", "id" => @ping_id)
          last_heartbeat = now
        end
        begin
          payload = database { RemoteAgentTransport.operations(@session) }
          payload.fetch("operations").each { |operation| send_json("type" => "operation", "operation" => operation) }
        rescue ActiveRecord::RecordNotFound, SecurityError
          close!
          break
        rescue StandardError => e
          Rails.logger.warn("Remote Agent WSS dispatch failed: #{e.class}: #{e.message}")
        end
        sleep POLL_INTERVAL
      end
    end

    def receive(raw)
      message = JSON.parse(raw)
      case message.fetch("type")
      when "pong"
        @last_pong = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      when "ping"
        send_json("type" => "pong", "id" => message.fetch("id"))
      when "heartbeat"
        advertisement = Api::RemoteAgentProtocolController.new.send(:normalized_advertisement, message)
        database { RemoteAgentTransport.heartbeat(@session, advertisement) }
        @last_pong = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      when "result"
        operation_id = message.fetch("operation_id")
        payload = message.reject { |key, _| key == "type" }
        result = database { RemoteAgentTransport.result(@session, operation_id, payload) }
        send_json(result.merge("type" => "ack"))
      else
        raise ArgumentError, "unknown WSS message type"
      end
    rescue JSON::ParserError, KeyError, ArgumentError, ActiveRecord::RecordInvalid
      send_json("type" => "error", "code" => "validation_failed")
    rescue ActiveRecord::RecordNotFound, SecurityError
      close!
    end

    def send_json(value)
      @driver_mutex.synchronize { @driver.text(JSON.generate(value)) unless @closed }
    end

    def database(&block)
      Rails.application.executor.wrap { ActiveRecord::Base.uncached(&block) }
    end

    def close!
      return if @closed
      @closed = true
      @io&.close rescue nil
    end
  end
end
