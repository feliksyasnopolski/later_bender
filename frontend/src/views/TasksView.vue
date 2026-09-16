<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { request } from '../api'
import { useAuthStore } from '../stores/auth'

const statuses = [{ id: 'backlog', label: 'Backlog' }, { id: 'ready', label: 'Ready' }, { id: 'doing', label: 'Doing' }, { id: 'done', label: 'Done' }]
const route = useRoute(); const router = useRouter(); const auth = useAuthStore()
const tasks = ref([]); const projects = ref([]); const project = ref(null); const selected = ref(null)
const loading = ref(true); const error = ref(''); const mutationError = ref(''); const busy = ref(false)
const projectFilter = ref(''); const priorityFilter = ref(''); const tagFilter = ref(''); const showDropped = ref(false)
const createOpen = ref(false); const newTitle = ref(''); const createStatus = ref('backlog'); const createProject = ref(''); const createError = ref('')
const isProject = computed(() => Boolean(route.params.project)); const scopeLabel = computed(() => project.value?.name || 'All tasks'); const selectedId = computed(() => route.params.taskId)
const visibleTasks = computed(() => tasks.value.filter((task) => (showDropped.value || task.status !== 'dropped') && (!projectFilter.value || task.project?.slug === projectFilter.value) && (!priorityFilter.value || task.priority === priorityFilter.value) && (!tagFilter.value || task.tags?.some((tag) => tag.toLowerCase().includes(tagFilter.value.toLowerCase())))))
const columns = computed(() => statuses.map((status) => ({ ...status, tasks: visibleTasks.value.filter((task) => task.status === status.id) })))

async function loadSelected(id) { try { selected.value = await request(`/tasks/${id}`, {}, auth.token) } catch (e) { mutationError.value = e.message; selected.value = null } }
async function load() {
  loading.value = true; error.value = ''
  try {
    const [data, projectData] = await Promise.all([request(isProject.value ? `/projects/${route.params.project}/tasks?summary=true` : '/tasks?summary=true', {}, auth.token), request('/projects', {}, auth.token)])
    tasks.value = data; projects.value = projectData; project.value = isProject.value ? projectData.find((item) => item.slug === route.params.project) || data[0]?.project : null
    if (isProject.value) createProject.value = route.params.project
    if (selectedId.value) await loadSelected(selectedId.value); else selected.value = null
  } catch (e) { error.value = e.message } finally { loading.value = false }
}
function taskPath(task) { return isProject.value ? `/projects/${task.project.slug}/tasks/${task.id}` : `/tasks/${task.id}` }
function openTask(task) { router.push(taskPath(task)) }
function closeTask() { router.push(isProject.value ? `/projects/${route.params.project}/tasks` : '/tasks') }
function beginCreate(status = 'backlog') { createOpen.value = true; createStatus.value = status; createError.value = ''; newTitle.value = ''; if (!createProject.value) createProject.value = project.value?.slug || projects.value[0]?.slug || '' }
async function createTask() {
  if (!newTitle.value.trim() || !createProject.value) return
  busy.value = true; createError.value = ''
  try { const task = await request(`/projects/${createProject.value}/tasks`, { method: 'POST', body: JSON.stringify({ title: newTitle.value.trim(), status: createStatus.value }) }, auth.token); tasks.value.unshift(task); createOpen.value = false; openTask(task) }
  catch (e) { createError.value = e.message } finally { busy.value = false }
}
async function updateTask(changes) {
  if (!selected.value) return
  busy.value = true; mutationError.value = ''
  try { selected.value = await request(`/tasks/${selected.value.id}`, { method: 'PATCH', body: JSON.stringify(changes) }, auth.token); const index = tasks.value.findIndex((task) => task.id === selected.value.id); if (index >= 0) tasks.value[index] = { ...tasks.value[index], ...selected.value } }
  catch (e) { mutationError.value = e.message; await loadSelected(selected.value.id) } finally { busy.value = false }
}
async function dropTask(task, status) {
  const oldStatus = task.status; if (oldStatus === status) return
  task.status = status; mutationError.value = ''
  try { const updated = await request(`/tasks/${task.id}`, { method: 'PATCH', body: JSON.stringify({ status }) }, auth.token); Object.assign(task, updated); if (selected.value?.id === task.id) selected.value = { ...selected.value, ...updated } }
  catch (e) { task.status = oldStatus; mutationError.value = `Could not move “${task.title}”: ${e.message}` }
}
function dragStart(event, task) { event.dataTransfer.effectAllowed = 'move'; event.dataTransfer.setData('text/task-id', String(task.id)) }
function dropColumn(event, status) { const task = tasks.value.find((item) => String(item.id) === event.dataTransfer.getData('text/task-id')); if (task) dropTask(task, status) }
watch(() => route.fullPath, () => { if (selectedId.value) loadSelected(selectedId.value); else selected.value = null })
onMounted(load)
</script>

<template>
  <section class="board-page"><div class="board-heading"><div><p class="eyebrow">Task board</p><h1>{{ scopeLabel }}</h1></div><button class="primary" @click="beginCreate()">+ New task</button></div>
    <form class="board-filters" @submit.prevent="load"><label v-if="!isProject">Project<select v-model="projectFilter"><option value="">All projects</option><option v-for="item in projects" :key="item.id" :value="item.slug">{{ item.name }}</option></select></label><label>Priority<select v-model="priorityFilter"><option value="">Any priority</option><option value="low">Low</option><option value="normal">Normal</option><option value="high">High</option></select></label><label>Tag<input v-model="tagFilter" placeholder="Filter tag" /></label><label class="check"><input v-model="showDropped" type="checkbox" /> Show dropped</label></form>
    <p v-if="error" class="error" role="alert">{{ error }} <button @click="load">Retry</button></p><p v-if="mutationError" class="error" role="alert">{{ mutationError }}</p><p v-if="loading" class="muted" role="status">Loading tasks…</p>
    <div v-else class="board" aria-label="Task board"><article v-for="column in columns" :key="column.id" class="board-column" @dragover.prevent @drop="dropColumn($event, column.id)"><header><h2>{{ column.label }}</h2><span>{{ column.tasks.length }}</span><button class="column-add" :aria-label="`Create task in ${column.label}`" @click="beginCreate(column.id)">+</button></header><div v-if="!column.tasks.length" class="column-empty">No tasks here.<button @click="beginCreate(column.id)">Create one</button></div><button v-for="task in column.tasks" :key="task.id" class="task-card" draggable="true" @dragstart="dragStart($event, task)" @click="openTask(task)"><strong>{{ task.title }}</strong><span v-if="!isProject" class="card-project">{{ task.project.name }}</span><span v-if="task.priority && task.priority !== 'normal'" class="priority" :class="`priority-${task.priority}`">{{ task.priority }}</span><span v-if="task.tags?.length" class="tags">{{ task.tags.join(' · ') }}</span></button></article></div>
    <div v-if="showDropped && visibleTasks.some((task) => task.status === 'dropped')" class="dropped-list"><h2>Dropped</h2><button v-for="task in visibleTasks.filter((item) => item.status === 'dropped')" :key="task.id" @click="openTask(task)">{{ task.title }}</button></div>
    <div v-if="createOpen" class="create-bar"><form @submit.prevent="createTask"><input v-model="newTitle" autofocus placeholder="Task title" required /><select v-model="createProject" :disabled="isProject"><option value="" disabled>Choose project</option><option v-for="item in projects" :key="item.id" :value="item.slug">{{ item.name }}</option></select><span class="create-status">{{ createStatus }}</span><button class="primary" :disabled="busy">Create</button><button type="button" @click="createOpen = false">Cancel</button></form><p v-if="createError" class="error">{{ createError }}</p></div>
    <aside v-if="selected" class="detail-pane" aria-label="Task details"><button class="close" aria-label="Close task details" @click="closeTask">×</button><p class="eyebrow">Task detail</p><h2>{{ selected.title }}</h2><p v-if="mutationError" class="error">{{ mutationError }}</p><label>Title<input :value="selected.title" @change="updateTask({ title: $event.target.value })" /></label><label>Status<select :value="selected.status" @change="updateTask({ status: $event.target.value })"><option v-for="item in [...statuses, { id: 'dropped', label: 'Dropped' }]" :key="item.id" :value="item.id">{{ item.label }}</option></select></label><label>Priority<select :value="selected.priority || ''" @change="updateTask({ priority: $event.target.value || null })"><option value="">No priority</option><option value="low">Low</option><option value="normal">Normal</option><option value="high">High</option></select></label><p class="field-label">Project</p><p class="readonly-field">{{ selected.project.name }}</p><label>Tags<input :value="selected.tags?.join(', ')" placeholder="comma separated" @change="updateTask({ tags: $event.target.value.split(',').map((tag) => tag.trim()).filter(Boolean) })" /></label><label>Context<textarea :value="selected.context || ''" rows="4" @change="updateTask({ context: $event.target.value })" /></label><label>Intended direction<textarea :value="selected.intended_direction || ''" rows="4" @change="updateTask({ intended_direction: $event.target.value })" /></label><section class="related"><h3>Related notes</h3><p v-if="!selected.related_notes?.length" class="muted">No related notes.</p><a v-for="note in selected.related_notes" :key="note.id" href="#">{{ note.title }}</a></section></aside>
  </section>
</template>
