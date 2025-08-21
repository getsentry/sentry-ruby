import { defineConfig } from "vite"
import { svelte } from "@sveltejs/vite-plugin-svelte"

export default defineConfig({
  plugins: [
    svelte(),
    {
      name: "health-check",
      configureServer(server) {
        server.middlewares.use("/health", (req, res, next) => {
          if (req.method === "GET") {
            res.setHeader("Content-Type", "application/json")
            res.setHeader("Access-Control-Allow-Origin", "*")
            res.end(JSON.stringify({
              status: "ok",
              timestamp: new Date().toISOString(),
              service: "svelte-mini"
            }))
          } else {
            next()
          }
        })
      }
    }
  ],
  server: {
    port: parseInt(process.env.SENTRY_E2E_SVELTE_APP_PORT),
    host: "0.0.0.0",
  },
  define: {
    SENTRY_E2E_RAILS_APP_URL: JSON.stringify(process.env.SENTRY_E2E_RAILS_APP_URL)
  },
  envPrefix: ["SENTRY_"]
})
