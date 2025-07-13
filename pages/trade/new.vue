<script setup>
  import { isSteamID64 } from '~/assets/js/validate';

  const supabase = useSupabaseClient();
  const route = useRoute();
  const { User } = useORM();

  const { data: resolvedPartnerId } = await useLazyAsyncData(`user-id-${route.query.partner}`, async () => {
    if (route.query.partner && isSteamID64(route.query.partner)) {
      const users = await User.query(supabase, [
        {
          filter: 'eq',
          params: [User.fields.steamId, route.query.partner]
        },
        {
          filter: 'limit',
          params: [1]
        }
      ]);

      if (users && users.length > 0) {
        return users[0].id;
      }
    }
    return route.query.partner;
  });

  definePageMeta({
    middleware: 'authenticated'
  });
</script>

<template>
  <trade-edit
    v-if="!route.query.partner || resolvedPartnerId"
    :copy-id="route.query.copy"
    :counter-id="route.query.counter"
    :receiver="resolvedPartnerId"
    :receiver-selected="route.query.receiverapps ? route.query.receiverapps.split(',').map(Number) : []"
    :sender-selected="route.query.senderapps ? route.query.senderapps.split(',').map(Number) : []"
  />
</template>
