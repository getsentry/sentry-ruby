import * as Sentry from "@sentry/svelte";
import App from './App.svelte'

Sentry.init({
    dsn: import.meta.env.SENTRY_DSN_JS,
    debug: true,
    integrations: [Sentry.browserTracingIntegration(), Sentry.replayIntegration()],
    tracesSampleRate: 1.0,
    replaysSessionSampleRate: 1.0,
    replaysOnErrorSampleRate: 1.0,
    tracePropagationTargets: ["localhost"],
});

const app = new App({
  target: document.getElementById('app'),
})

export default app
