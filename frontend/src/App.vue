<script setup>
import { useAuthStore } from './stores/auth'
import { useRouter } from 'vue-router'

const auth = useAuthStore()
const router = useRouter()

async function logout() {
  await auth.logout()
  router.push('/login')
}
</script>

<template>
  <header v-if="auth.isAuthenticated" class="site-header">
    <router-link to="/projects" class="brand">Later, Bender</router-link>
    <span>{{ auth.user.username }}</span>
    <button class="link-button" @click="logout">Log out</button>
  </header>
  <main class="page"><router-view /></main>
</template>
