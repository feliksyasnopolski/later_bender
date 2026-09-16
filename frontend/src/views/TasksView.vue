<script setup>
import { computed, onMounted, ref } from 'vue'
import { useRoute } from 'vue-router'
import { request } from '../api'
import { useAuthStore } from '../stores/auth'

const auth = useAuthStore()
const route = useRoute()
const tasks = ref([]); const project = ref(null); const loading = ref(true); const error = ref('')
const status = ref(''); const priority = ref(''); const tag = ref(''); const q = ref('')
const filteredTasks = computed(() => tasks.value)

async function load() {
  loading.value = true; error.value = ''
  const params = new URLSearchParams(Object.entries({ status: status.value, priority: priority.value, tag: tag.value, q: q.value }).filter(([, value]) => value))
  try {
    tasks.value = await request(`/projects/${route.params.project}/tasks${params.size ? `?${params}` : ''}`, {}, auth.token)
    project.value = tasks.value[0]?.project || { slug: route.params.project, name: route.params.project }
  } catch (e) { error.value = e.message }
  finally { loading.value = false }
}
onMounted(load)
</script>

<template>
  <section>
    <router-link to="/projects">← Projects</router-link>
    <h1>{{ project?.name || route.params.project }}</h1>
    <form class="filters" @submit.prevent="load"><input v-model="q" placeholder="Search tasks" /><input v-model="status" placeholder="Status" /><input v-model="priority" placeholder="Priority" /><input v-model="tag" placeholder="Tag" /><button>Filter</button></form>
    <p v-if="loading" class="muted">Loading tasks…</p><p v-else-if="error" class="error" role="alert">{{ error }}</p><p v-else-if="!filteredTasks.length" class="muted">No tasks found.</p>
    <div v-else class="task-list"><router-link v-for="task in filteredTasks" :key="task.id" :to="`/projects/${route.params.project}/tasks/${task.id}`" class="task-row"><strong>{{ task.title }}</strong><span>{{ task.status }}</span><span>{{ task.priority || '—' }}</span><span>{{ task.tags.join(', ') || '—' }}</span></router-link></div>
  </section>
</template>
