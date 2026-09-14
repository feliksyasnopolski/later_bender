import { createRouter, createWebHistory } from 'vue-router'
import { useAuthStore } from './stores/auth'
import LoginView from './views/LoginView.vue'
import ProjectsView from './views/ProjectsView.vue'
import TasksView from './views/TasksView.vue'
import TaskDetailView from './views/TaskDetailView.vue'

const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/', redirect: '/projects' },
    { path: '/login', component: LoginView, meta: { guest: true } },
    { path: '/projects', component: ProjectsView, meta: { auth: true } },
    { path: '/projects/:project/tasks', component: TasksView, meta: { auth: true } },
    { path: '/projects/:project/tasks/:taskId', component: TaskDetailView, meta: { auth: true } }
  ]
})

router.beforeEach(async (to) => {
  const auth = useAuthStore()
  if (auth.token && !auth.user && !auth.checking) await auth.restore()
  if (to.meta.auth && !auth.isAuthenticated) return '/login'
  if (to.meta.guest && auth.isAuthenticated) return '/projects'
})

export default router
