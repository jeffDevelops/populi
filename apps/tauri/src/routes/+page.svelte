<script lang="ts">
  import Stats from '../components/Stats.svelte'
  import { ModeWatcher } from 'mode-watcher'
</script>

<main class="container mx-auto py-8 flex flex-col items-center justify-center min-h-screen">
  <Stats />
</main>

<ModeWatcher />

<style>
  /* Global styles are now handled by Tailwind in app.css */
</style>
