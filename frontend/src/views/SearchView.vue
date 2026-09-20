<script setup>
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { request } from '../api'
import { useAuthStore } from '../stores/auth'

const route = useRoute()
const router = useRouter()
const auth = useAuthStore()

const query = ref(typeof route.query.q === 'string' ? route.query.q : '')
const projectFilter = ref(typeof route.query.project === 'string' ? route.query.project : '')
const kindFilter = ref(typeof route.query.kind === 'string' ? route.query.kind : '')
const statusFilter = ref(typeof route.query.status === 'string' ? route.query.status : '')
const tagFilter = ref(typeof route.query.tag === 'string' ? route.query.tag : '')
const projects = ref([])
const results = ref([])
const total = ref(0)
const loading = ref(false)
const error = ref('')
const searched = ref(false)
const selected = ref(null)
const detail = ref(null)
const detailLoading = ref(false)
const detailError = ref('')

const hasQuery = computed(() => query.value.trim().length > 0)

function searchParams() {
  const params = new URLSearchParams({ q: query.value.trim(), limit: '50' })
  if (projectFilter.value) params.set('project', projectFilter.value)
  if (kindFilter.value) params.set('kinds', kindFilter.value)
  if (statusFilter.value) params.set('task_statuses', statusFilter.value)
  const tags = tagFilter.value.split(',').map((tag) => tag.trim()).filter(Boolean)
  if (tags.length) params.set('tags', tags.join(','))
  return params
}

function routeQuery() {
  return Object.fromEntries([...searchParams().entries()].filter(([key]) => key !== 'limit'))
}

async function search({ updateRoute = true } = {}) {
  if (!hasQuery.value) return
  loading.value = true
  error.value = ''
  selected.value = null
  detail.value = null
  detailError.value = ''
  if (updateRoute) await router.replace({ name: 'search', query: routeQuery() })
  try {
    const payload = await request(`/search?${searchParams()}`, {}, auth.token)
    results.value = payload.results || []
    total.value = payload.total ?? results.value.length
    searched.value = true
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

function kindLabel(kind) {
  return { task: 'Task', note: 'Note', file: 'File' }[kind] || kind
}

function projectLabel(result) {
  return result.project?.name || 'Global'
}

function resultTitle(result) {
  return result.kind === 'file' ? result.filename || result.title : result.title
}

function fileReadPath(result, readOptions = {}) {
  const params = new URLSearchParams()
  if (readOptions.representation) params.set('representation', readOptions.representation)
  if (readOptions.locator) params.set('locator', JSON.stringify(readOptions.locator))
  const suffix = params.toString() ? `?${params}` : ''
  return `/files/by-ref/${encodeURIComponent(result.ref)}/read${suffix}`
}

async function openResult(result) {
  if (result.kind === 'task') {
    await router.push(`/tasks/${result.id}`)
    return
  }

  selected.value = result
  detail.value = null
  detailLoading.value = true
  detailError.value = ''
  try {
    detail.value = result.kind === 'note'
      ? await request(`/notes/${result.id}`, {}, auth.token)
      : await openFileResult(result)
  } catch (e) {
    detailError.value = e.message
  } finally {
    detailLoading.value = false
  }
}

async function openFileResult(result) {
  const file = await request(`/files/by-ref/${encodeURIComponent(result.ref)}`, {}, auth.token)
  const readable = file.representations?.find((representation) => ['text', 'markdown', 'html_text', 'pdf_text'].includes(representation.kind))
  if (!readable) return file

  const requestedRepresentation = result.match?.representation
  const representation = file.representations.some((item) => item.kind === requestedRepresentation)
    ? requestedRepresentation
    : readable.kind
  const locator = representation === requestedRepresentation ? result.match?.locator : null
  try {
    const read = await request(fileReadPath(result, { representation, locator }), {}, auth.token)
    return { ...file, read }
  } catch (e) {
    if (representation === readable.kind && !locator) throw e
    const read = await request(fileReadPath(result, { representation: readable.kind }), {}, auth.token)
    return { ...file, read }
  }
}

function closeDetail() {
  selected.value = null
  detail.value = null
  detailError.value = ''
}

function formatLocator(locator) {
  if (!locator) return ''
  if (locator.kind && locator.start != null && locator.end != null) return `${locator.kind} ${locator.start}–${locator.end}`
  return JSON.stringify(locator)
}

onMounted(async () => {
  try { projects.value = await request('/projects', {}, auth.token) }
  catch (e) { error.value = e.message }
  if (hasQuery.value) await search({ updateRoute: false })
})
</script>

<template>
  <section class="search-page">
    <div class="search-heading">
      <p class="eyebrow">Durable recall</p>
      <h1>Search Later, Bender</h1>
      <p class="muted search-intro">Search Tasks, Notes, and readable Files with natural language. Narrow the ranked results only when useful.</p>
    </div>

    <form class="search-form" @submit.prevent="search()">
      <div class="search-query-row">
        <label class="search-query">Search
          <input v-model="query" type="search" placeholder="What do you remember?" autocomplete="off" autofocus required />
        </label>
        <button class="primary search-submit" :disabled="loading || !hasQuery">{{ loading ? 'Searching…' : 'Search' }}</button>
      </div>

      <div class="search-filters" aria-label="Search filters">
        <label>Project
          <select v-model="projectFilter">
            <option value="">Any project or global</option>
            <option v-for="project in projects" :key="project.id" :value="project.slug">{{ project.name }}</option>
          </select>
        </label>
        <label>Kind
          <select v-model="kindFilter">
            <option value="">Tasks, Notes, Files</option>
            <option value="task">Tasks</option>
            <option value="note">Notes</option>
            <option value="file">Files</option>
          </select>
        </label>
        <label>Status
          <select v-model="statusFilter">
            <option value="">Any task status</option>
            <option value="backlog">Backlog</option>
            <option value="ready">Ready</option>
            <option value="doing">Doing</option>
            <option value="done">Done</option>
            <option value="dropped">Dropped</option>
          </select>
        </label>
        <label>Tags
          <input v-model="tagFilter" placeholder="all tags, comma separated" />
        </label>
      </div>
    </form>

    <p v-if="error" class="error" role="alert">{{ error }}</p>
    <p v-else-if="loading" class="muted" role="status">Searching durable state…</p>
    <div v-else-if="searched" class="search-results" aria-live="polite">
      <div class="search-results-heading">
        <h2>Results</h2>
        <span class="muted">{{ total }} ranked {{ total === 1 ? 'match' : 'matches' }}</span>
      </div>
      <p v-if="!results.length" class="muted">No matching durable state found.</p>
      <button v-for="result in results" :key="`${result.kind}-${result.ref || result.id}`" class="search-result" type="button" @click="openResult(result)">
        <span class="search-result-meta">
          <strong class="kind-pill">{{ kindLabel(result.kind) }}</strong>
          <span>{{ projectLabel(result) }}</span>
          <span v-if="result.kind === 'task' && result.status">{{ result.status }}</span>
          <span v-if="result.kind === 'task' && result.ref">{{ result.ref }}</span>
          <span v-if="result.kind === 'file' && result.ref">{{ result.ref }}</span>
        </span>
        <strong class="search-result-title">{{ resultTitle(result) }}</strong>
        <span class="search-snippet">{{ result.snippet }}</span>
        <span v-if="result.tags?.length" class="tags">{{ result.tags.join(' · ') }}</span>
        <span v-if="result.kind === 'file' && result.match?.locator" class="search-match">Matched {{ formatLocator(result.match.locator) }}</span>
      </button>
    </div>

    <aside v-if="selected" class="detail-pane search-detail" aria-label="Search result details">
      <button class="close" aria-label="Close search result details" @click="closeDetail">×</button>
      <p class="eyebrow">{{ kindLabel(selected.kind) }}</p>
      <h2>{{ resultTitle(selected) }}</h2>
      <p class="search-detail-meta">{{ projectLabel(selected) }}<span v-if="selected.ref"> · {{ selected.ref }}</span></p>
      <p v-if="detailLoading" class="muted" role="status">Loading canonical {{ selected.kind }}…</p>
      <p v-else-if="detailError" class="error" role="alert">{{ detailError }}</p>
      <template v-else-if="selected.kind === 'note' && detail">
        <p v-if="detail.tags?.length" class="tags">{{ detail.tags.join(' · ') }}</p>
        <div class="search-detail-prose">{{ detail.body || '—' }}</div>
      </template>
      <template v-else-if="selected.kind === 'file' && detail">
        <p class="muted">{{ detail.representation || selected.match?.representation || 'readable representation' }}<span v-if="detail.locator"> · {{ formatLocator(detail.locator) }}</span></p>
        <pre v-if="detail.read?.content" class="file-read">{{ detail.read.content }}</pre>
        <dl v-else class="file-metadata"><dt>Media type</dt><dd>{{ detail.media_type }}</dd><dt>Size</dt><dd>{{ detail.byte_size }} bytes</dd><dt>SHA-256</dt><dd>{{ detail.sha256 }}</dd></dl>
      </template>
    </aside>
  </section>
</template>
