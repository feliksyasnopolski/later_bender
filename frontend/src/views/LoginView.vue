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
  try { await auth.login(username.value, password.value); router.push(route.query.redirect || '/tasks') }
  catch (e) { error.value = e.message }
  finally { busy.value = false }
}
</script>

<template>
  <section class="login-page">
    <header class="login-brand"><h1>Later Bender</h1><p>Durable operational state for models and humans</p></header>
    <div class="narrow-card">
    <h2>Sign in</h2>
    <p class="muted">Continue to your Later Bender instance</p>
    <p v-if="error" class="error" role="alert">{{ error }}</p>
    <form @submit.prevent="submit">
      <label>Username<input v-model="username" autocomplete="username" required /></label>
      <label>Password<input v-model="password" type="password" autocomplete="current-password" required /></label>
      <button :disabled="busy">{{ busy ? 'Logging in…' : 'Log in' }}</button>
    </form>
    <p class="login-note">Self-hosted instance<br><span>Credentials stay with this Later Bender deployment.</span></p>
    </div><footer class="login-footer">later-bender</footer>
  </section>
</template>
