const apiBaseUrl = (import.meta.env.VITE_API_BASE_URL || 'http://localhost:3000').replace(/\/$/, '')

export class ApiError extends Error {
  constructor(message, status) {
    super(message)
    this.status = status
  }
}

export async function request(path, options = {}, token = null) {
  const headers = { Accept: 'application/json', ...(options.headers || {}) }
  if (options.body && !headers['Content-Type']) headers['Content-Type'] = 'application/json'
  if (token) headers.Authorization = `Bearer ${token}`

  const response = await fetch(`${apiBaseUrl}/api${path}`, { ...options, headers })
  if (response.status === 204) return null

  const payload = await response.json().catch(() => ({}))
  if (!response.ok) {
    const message = typeof payload.error === 'string' ? payload.error : payload.error?.message || `Request failed (${response.status})`
    throw new ApiError(message, response.status)
  }
  return payload
}

export { apiBaseUrl }
