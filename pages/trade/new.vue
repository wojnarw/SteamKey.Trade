<script setup>
  import { isSteamID64 } from '~/assets/js/validate';

  const supabase = useSupabaseClient();
  const { currentRoute } = useRouter();
  const { User } = useORM();

  const { data: resolvedPartnerId } = await useLazyAsyncData(`steamid-${currentRoute.query.partner}`, async () => {
    if (currentRoute.query.partner && isSteamID64(currentRoute.query.partner)) {
      const users = await User.query(supabase, [
        {
          filter: 'eq',
          params: [User.fields.steamId, currentRoute.query.partner]
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
    return currentRoute.query.partner;
  });

  definePageMeta({
    middleware: 'authenticated'
  });
</script>

<template>
  <trade-edit
    :copy-id="currentRoute.query.copy"
    :counter-id="currentRoute.query.counter"
    :receiver="resolvedPartnerId"
    :receiver-selected="currentRoute.query.receiverapps ? currentRoute.query.receiverapps.split(',').map(Number) : []"
    :sender-selected="currentRoute.query.senderapps ? currentRoute.query.senderapps.split(',').map(Number) : []"
  />
</template>
