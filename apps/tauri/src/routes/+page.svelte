<script lang="ts">
  import Stats from '../components/Stats.svelte'
  import { ModeWatcher } from 'mode-watcher'
</script>

<main class="container">
  <Stats />
</main>

<ModeWatcher />

<style>
  :root {
    font-family: Mona Sans;
    font-size: 16px;
    line-height: 24px;
    font-weight: 400;
    font-synthesis: none;
    text-rendering: optimizeLegibility;
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
    -webkit-text-size-adjust: 100%;
  }

  .container {
    margin: 0;
    display: flex;
    flex-direction: column;
    justify-content: center;
    text-align: center;
  }
</style>
