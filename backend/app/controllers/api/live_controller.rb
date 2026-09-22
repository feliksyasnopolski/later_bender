module Api
  class LiveController < BaseController
    include ActionController::Live

    def stream
      response.headers["Content-Type"] = "text/event-stream"
      response.headers["Cache-Control"] = "no-cache, no-transform"
      response.headers["X-Accel-Buffering"] = "no"
      response.headers["Connection"] = "keep-alive"
      queue = LiveEvents.subscribe(current_user.id)
      self.response_body = Enumerator.new do |body|
        body << ": connected\n\n"
        loop do
          begin
            event = Timeout.timeout(20) { queue.pop }
            body << "event: invalidation\ndata: #{event.json}\n\n"
          rescue Timeout::Error
            body << ": keep-alive\n\n"
          end
        end
      ensure
        LiveEvents.unsubscribe(current_user.id, queue)
      end
    end
  end
end
