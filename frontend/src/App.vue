<script setup>
import { useAuthStore } from './stores/auth'
import { useRoute, useRouter } from 'vue-router'
import { watch } from 'vue'

const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

watch(() => auth.token, (token) => {
  if (!token && route.meta.auth) router.replace({ path: '/login', query: { redirect: route.fullPath } })
})

async function logout() {
  await auth.logout()
  router.push('/login')
}
</script>

<template>
  <div v-if="auth.isAuthenticated" class="app-shell">
    <header class="site-header">
      <router-link to="/projects" class="brand">Later, Bender</router-link>
      <nav class="primary-nav" aria-label="Primary navigation">
        <router-link to="/tasks" :class="{ active: route.path === '/tasks' || route.path.includes('/tasks') }">Tasks</router-link>
        <router-link to="/notes" active-class="active">Notes</router-link>
        <router-link to="/projects" :class="{ active: route.path === '/projects' }">Projects</router-link>
        <router-link to="/search" active-class="active">Search</router-link>
      </nav>
      <div class="account-menu">
        <span class="username">{{ auth.user.username }}</span>
        <button class="link-button" @click="logout">Log out</button>
      </div>
    </header>
    <main class="page"><router-view /></main>
  </div>
  <main v-else class="page"><router-view /></main>
</template>
