<script lang="ts">
  import {
    Tag,
    Scan,
    MapPin,
    WifiSync,
    Binoculars,
    Smartphone,
    ArrowLeftRight,
  } from '@lucide/svelte'
  import {
    PUBLIC_INSTANCE_ID,
    PUBLIC_COTURN_PORT,
    PUBLIC_COTURN_HOSTS,
    PUBLIC_LOCATION_LAT,
    PUBLIC_LOCATION_LONG,
    PUBLIC_SIGNALING_HOSTS,
  } from '$env/static/public'
  import * as Card from '$lib/components/ui/card/index'
  import * as Accordion from '$lib/components/ui/accordion/index'

  const stunHosts = JSON.parse(PUBLIC_COTURN_HOSTS)
  const turnHosts = JSON.parse(PUBLIC_COTURN_HOSTS)
  const signalingHosts = JSON.parse(PUBLIC_SIGNALING_HOSTS)
</script>

<Card.Root class="w-full mb-2">
  <Accordion.Root type="multiple" class="pb-0">
    <Accordion.Item>
      <Accordion.Trigger class="py-0 px-4">
        <Card.Title class="flex flex-row justify-between w-full">
          <div>Network Details</div>
          <div class="flex items-center gap-2">
            <Tag size="1rem" class="text-muted-foreground" />
            <span class="font-mono">{PUBLIC_INSTANCE_ID}</span>
          </div>
        </Card.Title>
      </Accordion.Trigger>

      <Accordion.Content class="flex flex-col gap-4 text-balance mt-4 pb-0">
        <Card.Content class="flex flex-col gap-2 px-4">
          {#if signalingHosts.length > 1}
            <Accordion.Root type="single">
              <Accordion.Item value="item-1">
                <Accordion.Trigger>
                  <div class="flex items-center gap-2">
                    <Binoculars size="1rem" class="text-muted-foreground" />
                    <span class="font-semibold text-muted-foreground text-xs"
                      >Signaling Hosts</span
                    >
                  </div>
                </Accordion.Trigger>
                <Accordion.Content class="flex flex-col gap-4 text-balance">
                  {#each signalingHosts as host}
                    <Accordion.Item>
                      <div class="flex items-center gap-2">
                        <span class="font-mono"
                          >{host}:{PUBLIC_COTURN_PORT}</span
                        >
                      </div>
                    </Accordion.Item>
                  {/each}
                </Accordion.Content>
              </Accordion.Item>
            </Accordion.Root>
          {:else}
            <div class="flex items-center gap-2">
              <Binoculars size="1rem" class="text-muted-foreground" />
              <span class="font-semibold text-muted-foreground"
                >Signaling Host</span
              >
              <span class="font-mono">{signalingHosts[0]}</span>
            </div>
          {/if}

          {#if stunHosts.length > 1}
            <Accordion.Root type="single">
              <Accordion.Item value="item-1">
                <Accordion.Trigger>
                  <div class="flex items-center gap-2">
                    <Scan size="1rem" class="text-muted-foreground" />
                    <span class="font-semibold text-muted-foreground"
                      >STUN Hosts</span
                    >
                  </div>
                </Accordion.Trigger>
                <Accordion.Content class="flex flex-col gap-4 text-balance">
                  {#each stunHosts as host}
                    <Accordion.Item>
                      <div class="flex items-center gap-2">
                        <span class="font-mono"
                          >{host}:{PUBLIC_COTURN_PORT}</span
                        >
                      </div>
                    </Accordion.Item>
                  {/each}
                </Accordion.Content>
              </Accordion.Item>
            </Accordion.Root>
          {:else}
            <div class="flex items-center gap-2">
              <Scan size="1rem" class="text-muted-foreground" />
              <span class="font-semibold text-muted-foreground">STUN Host</span>
              <span class="font-mono">{stunHosts[0]}:{PUBLIC_COTURN_PORT}</span>
            </div>
          {/if}

          {#if turnHosts.length > 1}
            <Accordion.Root type="single">
              <Accordion.Item value="item-1">
                <Accordion.Trigger>
                  <div class="flex items-center gap-2">
                    <WifiSync size="1rem" class="text-primary" />
                    <span class="font-semibold">TURN Hosts</span>
                  </div>
                </Accordion.Trigger>
                <Accordion.Content class="flex flex-col gap-4 text-balance">
                  {#each turnHosts as host}
                    <Accordion.Item>
                      <div class="flex items-center gap-2">
                        <span class="font-mono"
                          >{host}:{PUBLIC_COTURN_PORT}</span
                        >
                      </div>
                    </Accordion.Item>
                  {/each}
                </Accordion.Content>
              </Accordion.Item>
            </Accordion.Root>
          {:else}
            <div class="flex items-center gap-2">
              <WifiSync size="1rem" class="text-muted-foreground" />
              <span class="font-semibold text-muted-foreground">TURN Host</span>
              <span class="font-mono">{turnHosts[0]}:{PUBLIC_COTURN_PORT}</span>
            </div>
          {/if}

          <div class="flex flex-row gap-2 justify-start">
            <div class="flex gap-2 items-start mt-1">
              <MapPin size="1rem" class="text-muted-foreground" />
            </div>
            <div class="flex flex-col items-start">
              <div class="flex flex-row gap-2">
                <span class="font-semibold inline-block text-muted-foreground"
                  >Lat</span
                >
                <span class="font-mono inline-block">{PUBLIC_LOCATION_LAT}</span
                >
              </div>
              <div class="flex flex-row gap-2">
                <span class="font-semibold inline-block text-muted-foreground"
                  >Lon</span
                >
                <span class="font-mono inline-block"
                  >{PUBLIC_LOCATION_LONG}</span
                >
              </div>
            </div>
          </div>
        </Card.Content>
      </Accordion.Content>
    </Accordion.Item>
  </Accordion.Root>
</Card.Root>

<Card.Root class="w-full">
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
