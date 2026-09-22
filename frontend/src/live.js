import { apiBaseUrl } from './api'

let stop = null

export function startLive(token, onEvent) {
  stop?.()
  if (!token) return () => {}
  let cancelled = false
  let controller = null
  let retryTimer = null
  let connected = false

  const run = async () => {
    controller = new AbortController()
    try {
      const response = await fetch(`${apiBaseUrl}/api/live`, { headers: { Accept: 'text/event-stream', Authorization: `Bearer ${token}` }, signal: controller.signal })
      if (!response.ok || !response.body) throw new Error('live stream unavailable')
      if (connected) onEvent({ type: 'live.reconnected' })
      connected = true
      const reader = response.body.getReader()
      const decoder = new TextDecoder()
      let buffer = ''
      while (!cancelled) {
        const { value, done } = await reader.read()
        if (done) throw new Error('live stream closed')
        buffer += decoder.decode(value, { stream: true })
        const messages = buffer.split(/\n\n/)
        buffer = messages.pop() || ''
        for (const message of messages) {
          const line = message.split('\n').find((item) => item.startsWith('data:'))
          if (!line) continue
          try { onEvent(JSON.parse(line.slice(5).trim())) } catch { /* malformed future events are harmless */ }
        }
      }
    } catch {
      if (!cancelled) retryTimer = setTimeout(run, 2000)
    }
  }
  run()
  stop = () => { cancelled = true; controller?.abort(); clearTimeout(retryTimer); if (stop) stop = null }
  return stop
}
