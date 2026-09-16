import { createApp } from 'vue'
import { createPinia, setActivePinia } from 'pinia'
import App from './App.vue'
import router from './router'
import { setUnauthorizedHandler } from './api'
import { useAuthStore } from './stores/auth'
import './style.css'

const pinia = createPinia()
setActivePinia(pinia)
const auth = useAuthStore(pinia)
setUnauthorizedHandler(() => auth.clear())
createApp(App).use(pinia).use(router).mount('#app')
