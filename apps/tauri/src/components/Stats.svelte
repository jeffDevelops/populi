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

<Card.Root class="w-full max-w-sm">
  <Card.Header>
    <Card.Title>Login to your account</Card.Title>
    <Card.Description
      >Enter your email below to login to your account</Card.Description
    >
    <Card.Action></Card.Action>
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
  <Card.Footer class="flex-col gap-2"></Card.Footer>
</Card.Root>

<Card.Root>
  <Card.Header>
    <Card.Title>Network Details</Card.Title>
  </Card.Header>

  <h2>
    <Tag size="1rem" />
    {PUBLIC_INSTANCE_ID}
  </h2>
  <h2>
    <WifiSync size="1rem" /> <span>STUN</span>
    {PUBLIC_COTURN_HOST}:{PUBLIC_COTURN_PORT}
  </h2>
  <h2>
    <WifiSync size="1rem" /> <span>TURN</span>
    {PUBLIC_COTURN_HOST}:{PUBLIC_COTURN_PORT}
  </h2>
  <div class="container">
    <h2><MapPin size="1rem" /> <span>Lat</span>{PUBLIC_LOCATION_LAT}</h2>
    <h2><MapPin size="1rem" /> <span>Lon</span>{PUBLIC_LOCATION_LONG}</h2>
  </div>
</Card.Root>

<section>
  <div class="container">
    <h2>
      <Smartphone size="1rem" />
      <ArrowLeftRight size="1rem" />
      <Smartphone size="1rem" /> <span>Known Peers</span>
    </h2>
  </div>
</section>

<style>
  section {
    margin: 1rem;
    padding: 1rem;
    border-radius: 0.5rem;
    background-color: #232323;
  }

  span {
    font-weight: 700;
  }

  .container {
    display: flex;
    flex-direction: column;
    justify-content: center;
    align-items: flex-start;
  }

  h2 {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    text-align: center;
    font-family: Mona Sans;
    letter-spacing: 0.1rem;
    text-transform: uppercase;
    font-weight: 400;
    font-size: 1rem;
  }
</style>
