<script>
  let loading = false;
  let result = "";

  let jobLoading = false;
  let jobResult = "";

  async function triggerError() {
    loading = true;
    try {
      const response = await fetch(`${SENTRY_E2E_RAILS_APP_URL}/error`, {
        method: "GET",
        headers: {
          "Content-Type": "application/json",
        },
      });

      if (response.ok) {
        const data = await response.json();
        result = `Success: ${JSON.stringify(data)}`;
      } else {
        result = `Error: ${response.status} ${response.statusText}`;
      }
    } catch (error) {
      result = `Error: ${error.message}`;
    } finally {
      loading = false;
    }
  }

  async function triggerJob() {
    jobLoading = true;
    try {
      const response = await fetch(`${SENTRY_E2E_RAILS_APP_URL}/jobs/sample`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
      });

      if (response.ok) {
        const data = await response.json();
        jobResult = `Job: ${JSON.stringify(data)}`;
      } else {
        jobResult = `Error: ${response.status} ${response.statusText}`;
      }
    } catch (error) {
      jobResult = `Error: ${error.message}`;
    } finally {
      jobLoading = false;
    }
  }
</script>

<main>
  <h1>Svelte Mini App</h1>
  <p>
    Click the button to trigger an error in the Rails app and test distributed
    tracing:
  </p>

  <button id="trigger-error-btn" on:click={triggerError} disabled={loading}>
    {loading ? "Loading..." : "Trigger Error"}
  </button>

  {#if result}
    <div class="result">
      <h3>Result:</h3>
      <pre>{result}</pre>
    </div>
  {/if}

  <p>
    Click the button to enqueue an ActiveJob in the Rails app — distributed
    tracing should connect this fetch, the Rails controller, the
    <code>queue.publish</code> span, and the async-executed job:
  </p>

  <button id="trigger-job-btn" on:click={triggerJob} disabled={jobLoading}>
    {jobLoading ? "Loading..." : "Trigger Job"}
  </button>

  {#if jobResult}
    <div class="result">
      <h3>Job result:</h3>
      <pre>{jobResult}</pre>
    </div>
  {/if}
</main>

<style>
  main {
    text-align: center;
    padding: 1em;
    max-width: 240px;
    margin: 0 auto;
  }

  button {
    background-color: #ff3e00;
    color: white;
    border: none;
    padding: 10px 20px;
    border-radius: 5px;
    cursor: pointer;
    font-size: 16px;
    margin: 20px 0;
  }

  button:disabled {
    background-color: #ccc;
    cursor: not-allowed;
  }

  .result {
    margin-top: 20px;
    text-align: left;
    background-color: #f5f5f5;
    padding: 10px;
    border-radius: 5px;
  }

  pre {
    white-space: pre-wrap;
    word-break: break-word;
  }
</style>
