import { onBeforeUnmount, onMounted } from 'vue'

export function useLiveInvalidation(load, types) {
  const handler = (event) => { if (event.detail?.type === 'live.reconnected' || types.includes(event.detail?.type)) load() }
  onMounted(() => window.addEventListener('lb:invalidation', handler))
  onBeforeUnmount(() => window.removeEventListener('lb:invalidation', handler))
}
