<script lang="ts">
  import {
    Tag,
    WifiSync,
    MapPin,
    ArrowLeftRight,
    Smartphone,
  } from '@lucide/svelte'
  import {
    PUBLIC_INSTANCE_ID,
    PUBLIC_COTURN_HOST,
    PUBLIC_COTURN_PORT,
    PUBLIC_LOCATION_LAT,
    PUBLIC_LOCATION_LONG,
    PUBLIC_SIGNALING_HOSTS,
  } from '$env/static/public'
  import * as Card from '$lib/components/ui/card/index'
</script>

<Card.Root class="w-full max-w-sm mb-4">
  <Card.Header>
    <Card.Title>Login to your account</Card.Title>
    <Card.Description>Enter your email below to login to your account</Card.Description>
  </Card.Header>
  <Card.Content>
    <form>
      <div class="flex flex-col gap-6">
        <div class="grid gap-2"></div>
        <div class="grid gap-2">
          <div class="flex items-center">
            <a
              href="##"
              class="ml-auto inline-block text-sm underline-offset-4 hover:underline"
            >
              Forgot your password?
            </a>
          </div>
        </div>
      </div>
    </form>
  </Card.Content>
  <Card.Footer class="flex justify-end"></Card.Footer>
</Card.Root>

<Card.Root class="w-full max-w-sm mb-4">
  <Card.Header>
    <Card.Title>Network Details</Card.Title>
  </Card.Header>
  <Card.Content class="flex flex-col gap-2">
    <div class="flex items-center gap-2">
      <Tag size="1rem" class="text-primary" />
      <span class="font-mono">{PUBLIC_INSTANCE_ID}</span>
    </div>
    <div class="flex items-center gap-2">
      <WifiSync size="1rem" class="text-primary" /> 
      <span class="font-semibold">STUN</span>
      <span class="font-mono">{PUBLIC_COTURN_HOST}:{PUBLIC_COTURN_PORT}</span>
    </div>
    <div class="flex items-center gap-2">
      <WifiSync size="1rem" class="text-primary" /> 
      <span class="font-semibold">TURN</span>
      <span class="font-mono">{PUBLIC_COTURN_HOST}:{PUBLIC_COTURN_PORT}</span>
    </div>
    <div class="grid grid-cols-2 gap-2 mt-2">
      <div class="flex items-center gap-2">
        <MapPin size="1rem" class="text-primary" /> 
        <span class="font-semibold">Lat</span>
        <span class="font-mono">{PUBLIC_LOCATION_LAT}</span>
      </div>
      <div class="flex items-center gap-2">
        <MapPin size="1rem" class="text-primary" /> 
        <span class="font-semibold">Lon</span>
        <span class="font-mono">{PUBLIC_LOCATION_LONG}</span>
      </div>
    </div>
  </Card.Content>
</Card.Root>

<Card.Root class="w-full max-w-sm">
  <Card.Header>
    <Card.Title class="flex items-center gap-2">
      <Smartphone size="1rem" />
      <ArrowLeftRight size="1rem" />
      <Smartphone size="1rem" /> 
      <span>Known Peers</span>
    </Card.Title>
  </Card.Header>
  <Card.Content>
    <!-- Peer content will go here -->
    <p class="text-muted-foreground">No peers connected</p>
  </Card.Content>
</Card.Root>

<style>
  /* Only keep styles that don't conflict with Tailwind */
  /* Custom styles can be added here if needed */
</style>
