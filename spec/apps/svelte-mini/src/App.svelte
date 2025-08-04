<script>
  let loading = false;
  let result = '';

  async function triggerError() {
    loading = true;
    try {
      const response = await fetch(`${__RAILS_API_URL__}/error`, {
        method: 'GET',
        headers: {
          'Content-Type': 'application/json',
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
</script>

<main>
  <h1>Svelte Mini App</h1>
  <p>Click the button to trigger an error in the Rails app and test distributed tracing:</p>

  <button
    id="trigger-error-btn"
    on:click={triggerError}
    disabled={loading}
  >
    {loading ? 'Loading...' : 'Trigger Error'}
  </button>

  {#if result}
    <div class="result">
      <h3>Result:</h3>
      <pre>{result}</pre>
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
