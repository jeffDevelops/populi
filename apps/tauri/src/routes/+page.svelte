<script lang="ts">
  import Stats from '../components/Stats.svelte'
  import { ModeWatcher } from 'mode-watcher'
</script>

<ModeWatcher />
<main class="mt-2 flex flex-col px-1 min-h-screen">
  <Stats />
</main>
