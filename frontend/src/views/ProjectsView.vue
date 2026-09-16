<script setup>
import { onMounted, ref } from 'vue'
import { request } from '../api'
import { useAuthStore } from '../stores/auth'

const auth = useAuthStore()
const projects = ref([])
const error = ref('')
const loading = ref(true)

onMounted(async () => {
  try { projects.value = await request('/projects', {}, auth.token) }
  catch (e) { error.value = e.message }
  finally { loading.value = false }
})
</script>

<template>
  <section>
    <h1>Projects</h1>
    <p v-if="loading" class="muted">Loading projects…</p>
    <p v-else-if="error" class="error" role="alert">{{ error }}</p>
    <p v-else-if="!projects.length" class="muted">No projects yet.</p>
    <div v-else class="cards">
      <router-link v-for="project in projects" :key="project.id" :to="`/projects/${project.slug}/tasks`" class="card">
        <h2>{{ project.name }}</h2><p class="slug">{{ project.slug }}</p>
        <p v-if="project.description">{{ project.description }}</p>
        <small>{{ project.task_count }} tasks</small>
      </router-link>
    </div>
  </section>
</template>
