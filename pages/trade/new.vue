<script setup>
  const { currentRoute } = useRouter();

  definePageMeta({
    middleware: 'authenticated'
  });
</script>

<template>
  <trade-edit
    :copy-id="currentRoute.query.copy"
    :counter-id="currentRoute.query.counter"
    :receiver="currentRoute.query.partner"
    :receiver-selected="currentRoute.query.receiverapps ? currentRoute.query.receiverapps.split(',').map(Number) : []"
    :sender-selected="currentRoute.query.senderapps ? currentRoute.query.senderapps.split(',').map(Number) : []"
  />
</template>
