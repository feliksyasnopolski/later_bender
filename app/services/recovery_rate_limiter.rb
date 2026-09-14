class RecoveryRateLimiter
  LIMIT = 5
  WINDOW = 60
  @mutex = Mutex.new
  @attempts = Hash.new { |hash, key| hash[key] = [] }

  def self.allowed?(ip, username)
    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    keys = [ "ip:#{ip}", "user:#{username.to_s.downcase}" ]
    @mutex.synchronize do
      return false if keys.any? do |key|
        @attempts[key].reject! { |time| now - time >= WINDOW }
        @attempts[key].length >= LIMIT
      end

      keys.each { |key| @attempts[key] << now }
      true
    end
  end
end
