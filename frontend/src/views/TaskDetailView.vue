<script setup>
import { onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { request } from '../api'
import { useAuthStore } from '../stores/auth'

const route = useRoute(); const auth = useAuthStore(); const task = ref(null); const error = ref(''); const loading = ref(true)
onMounted(async () => { try { task.value = await request(`/projects/${route.params.project}/tasks/${route.params.taskId}`, {}, auth.token) } catch (e) { error.value = e.message; if (e.status === 401) auth.clear() } finally { loading.value = false } })
</script>

<template>
  <section><router-link :to="`/projects/${route.params.project}/tasks`">← Tasks</router-link><p v-if="loading" class="muted">Loading task…</p><p v-else-if="error" class="error" role="alert">{{ error }}</p><article v-else class="detail"><h1>{{ task.title }}</h1><dl><dt>Status</dt><dd>{{ task.status }}</dd><dt>Priority</dt><dd>{{ task.priority || '—' }}</dd><dt>Tags</dt><dd>{{ task.tags.join(', ') || '—' }}</dd><dt>Project</dt><dd>{{ task.project.name }} ({{ task.project.slug }})</dd><dt>Created</dt><dd>{{ task.created_at }}</dd><dt>Updated</dt><dd>{{ task.updated_at }}</dd></dl><h2>Context</h2><p class="prose">{{ task.context || '—' }}</p><h2>Intended direction</h2><p class="prose">{{ task.intended_direction || '—' }}</p></article></section>
</template>
