<script setup>
import { ref } from 'vue'
import { useRouter } from 'vue-router'
import { useRoute } from 'vue-router'
import { useAuthStore } from '../stores/auth'

const username = ref('')
const password = ref('')
const error = ref('')
const busy = ref(false)
const auth = useAuthStore()
const router = useRouter()
const route = useRoute()

async function submit() {
  error.value = ''
  busy.value = true
  try { await auth.login(username.value, password.value); router.push(route.query.redirect || '/projects') }
  catch (e) { error.value = e.message }
  finally { busy.value = false }
}
</script>

<template>
  <section class="narrow-card">
    <h1>Log in</h1>
    <p class="muted">Read-only access to your Later, Bender projects.</p>
    <p v-if="error" class="error" role="alert">{{ error }}</p>
    <form @submit.prevent="submit">
      <label>Username<input v-model="username" autocomplete="username" required /></label>
      <label>Password<input v-model="password" type="password" autocomplete="current-password" required /></label>
      <button :disabled="busy">{{ busy ? 'Logging in…' : 'Log in' }}</button>
    </form>
  </section>
</template>
