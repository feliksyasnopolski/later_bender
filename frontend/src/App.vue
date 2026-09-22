<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from './stores/auth'
import { request } from './api'
import { startLive } from './live'
const auth = useAuthStore(); const route = useRoute(); const router = useRouter()
const projects = ref([]); const projectSlug = ref('')
const nav = [{ label: 'Tasks', to: '/tasks' }, { label: 'Search', to: '/search' }, { label: 'Notes', to: '/notes' }, { label: 'Files', to: '/files' }, { label: 'Workspaces', to: '/workspaces' }, { label: 'Agents', to: '/agents' }, { label: 'Credentials', to: '/credentials' }]
const isAuthed = computed(() => auth.isAuthenticated)
const active = (to) => route.path === to || route.path.startsWith(`${to}/`)
async function loadProjects() { try { projects.value = await request('/projects', {}, auth.token) } catch { projects.value = [] } }
function chooseProject() { router.push(projectSlug.value ? `/projects/${projectSlug.value}/tasks` : '/tasks') }
let stopLive = () => {}
async function logout() { stopLive(); await auth.logout(); router.push('/login') }
function handleLiveEvent(event) { window.dispatchEvent(new CustomEvent('lb:invalidation', { detail: event })) }
watch(() => auth.isAuthenticated, (value) => { if (value) loadProjects() }, { immediate: true })
watch(() => route.params.project, (value) => { projectSlug.value = value || '' }, { immediate: true })
onMounted(() => { if (isAuthed.value) { loadProjects(); stopLive = startLive(auth.token, handleLiveEvent) } })
watch(() => auth.token, (token) => { stopLive(); stopLive = token ? startLive(token, handleLiveEvent) : () => {} })
</script>
<template>
  <div v-if="auth.token && auth.checking" class="session-loading">Checking your session…</div>
  <div v-else-if="isAuthed" class="app-shell">
    <aside class="sidebar"><router-link class="brand" to="/tasks">Later Bender</router-link><select v-model="projectSlug" class="project-scope" aria-label="Project scope" @change="chooseProject"><option value="">later-bender</option><option v-for="project in projects" :key="project.slug" :value="project.slug">{{ project.name }}</option></select><nav class="primary-nav" aria-label="Primary navigation"><router-link v-for="item in nav" :key="item.to" :to="item.to" :class="{ active: active(item.to) }">{{ item.label }}</router-link></nav><div class="sidebar-footer"><span>{{ auth.user?.username }}</span><button @click="logout">Log out</button></div></aside>
    <main class="app-content"><router-view /></main>
  </div><main v-else class="guest-content"><router-view /></main>
</template>
