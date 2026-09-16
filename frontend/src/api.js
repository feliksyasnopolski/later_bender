const apiBaseUrl = (import.meta.env.VITE_API_BASE_URL || 'http://localhost:3000').replace(/\/$/, '')

export class ApiError extends Error {
  constructor(message, status, details = null) {
    super(message)
    this.status = status
    this.details = details
  }
}

let unauthorizedHandler = null

export function setUnauthorizedHandler(handler) {
  unauthorizedHandler = handler
}

export async function request(path, options = {}, token = null) {
  const headers = { Accept: 'application/json', ...(options.headers || {}) }
  if (options.body && !headers['Content-Type']) headers['Content-Type'] = 'application/json'
  if (token) headers.Authorization = `Bearer ${token}`

  let response
  try {
    response = await fetch(`${apiBaseUrl}/api${path}`, { ...options, headers })
  } catch (error) {
    throw new ApiError(error.message || 'Unable to reach the Later, Bender API.', 0)
  }
  if (response.status === 204) return null

  const payload = await response.json().catch(() => ({}))
  if (!response.ok) {
    const message = typeof payload.error === 'string' ? payload.error : payload.error?.message || `Request failed (${response.status})`
    if (response.status === 401) unauthorizedHandler?.()
    throw new ApiError(message, response.status, payload)
  }
  return payload
}

export { apiBaseUrl }
