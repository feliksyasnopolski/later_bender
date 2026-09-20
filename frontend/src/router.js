import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from './stores/auth'
import LoginView from './views/LoginView.vue'
import TasksView from './views/TasksView.vue'
import SearchView from './views/SearchView.vue'
import NotesView from './views/NotesView.vue'
import FilesView from './views/FilesView.vue'
import WorkspacesView from './views/WorkspacesView.vue'
import CredentialsView from './views/CredentialsView.vue'
const routes = [
  { path: '/', redirect: '/tasks' }, { path: '/login', component: LoginView, meta: { guest: true } },
  { path: '/tasks', name: 'tasks', component: TasksView, meta: { auth: true } }, { path: '/tasks/:taskId', name: 'task', component: TasksView, meta: { auth: true } },
  { path: '/projects/:project/tasks', name: 'project-tasks', component: TasksView, meta: { auth: true } }, { path: '/projects/:project/tasks/:taskId', name: 'project-task', component: TasksView, meta: { auth: true } },
  { path: '/search', name: 'search', component: SearchView, meta: { auth: true } }, { path: '/notes', name: 'notes', component: NotesView, meta: { auth: true } }, { path: '/files', name: 'files', component: FilesView, meta: { auth: true } }, { path: '/workspaces', name: 'workspaces', component: WorkspacesView, meta: { auth: true } }, { path: '/credentials', name: 'credentials', component: CredentialsView, meta: { auth: true } }, { path: '/credentials/new', name: 'new-credential', component: CredentialsView, meta: { auth: true } },
]
const router = createRouter({ history: createWebHistory(), routes })
router.beforeEach(async (to) => { const auth = useAuthStore(); if (auth.token && !auth.user && !auth.checking) await auth.restore(); if (to.meta.auth && !auth.isAuthenticated) return { path: '/login', query: { redirect: to.fullPath } }; if (to.meta.guest && auth.isAuthenticated) return '/tasks' })
export default router
