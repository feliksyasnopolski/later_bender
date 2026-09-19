import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from './stores/auth'
import LoginView from './views/LoginView.vue'
import ProjectsView from './views/ProjectsView.vue'
import TasksView from './views/TasksView.vue'
import PlaceholderView from './views/PlaceholderView.vue'
import SearchView from './views/SearchView.vue'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', redirect: '/projects' },
    { path: '/login', component: LoginView, meta: { guest: true } },
    { path: '/tasks', name: 'tasks', component: TasksView, meta: { auth: true } },
    { path: '/tasks/:taskId', name: 'task', component: TasksView, meta: { auth: true } },
    { path: '/notes', name: 'notes', component: PlaceholderView, props: { title: 'Notes', message: 'Notes will live here.' }, meta: { auth: true } },
    { path: '/search', name: 'search', component: SearchView, meta: { auth: true } },
    { path: '/projects', component: ProjectsView, meta: { auth: true } },
    { path: '/projects/:project/tasks', name: 'project-tasks', component: TasksView, meta: { auth: true } },
    { path: '/projects/:project/tasks/:taskId', name: 'project-task', component: TasksView, meta: { auth: true } }
  ]
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  if (auth.token && !auth.user && !auth.checking) await auth.restore()
  if (to.meta.auth && !auth.isAuthenticated) return { path: '/login', query: { redirect: to.fullPath } }
  if (to.meta.guest && auth.isAuthenticated) return '/projects'
})

export default router
