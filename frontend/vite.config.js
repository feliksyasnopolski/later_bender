import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  server: { proxy: { '/api': process.env.VITE_PROXY_TARGET || 'http://127.0.0.1:3100' } },
})
