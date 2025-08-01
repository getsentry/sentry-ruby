import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'

export default defineConfig({
  plugins: [svelte()],
  server: {
    port: 5001,
    host: '0.0.0.0',
    allowedHosts: ['sentry-svelte-mini']
  },
  define: {
    __RAILS_API_URL__: JSON.stringify(process.env.SENTRY_E2E_RAILS_APP_URL || 'http://localhost:5000')
  }
})
