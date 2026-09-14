import { defineStore } from 'pinia'
import { request } from '../api'

const storageKey = 'later-bender-token'

export const useAuthStore = defineStore('auth', {
  state: () => ({ token: localStorage.getItem(storageKey), user: null, checking: false }),
  getters: { isAuthenticated: (state) => Boolean(state.token && state.user) },
  actions: {
    async login(username, password) {
      const session = await request('/auth/login', { method: 'POST', body: JSON.stringify({ username, password }) })
      this.token = session.token
      this.user = session.user
      localStorage.setItem(storageKey, session.token)
    },
    async restore() {
      if (!this.token) return false
      this.checking = true
      try {
        this.user = await request('/auth/current', {}, this.token)
        return true
      } catch (error) {
        if (error.status === 401) this.clear()
        return false
      } finally {
        this.checking = false
      }
    },
    async logout() {
      try { if (this.token) await request('/auth/logout', { method: 'DELETE' }, this.token) } finally { this.clear() }
    },
    clear() {
      this.token = null
      this.user = null
      localStorage.removeItem(storageKey)
    }
  }
})
