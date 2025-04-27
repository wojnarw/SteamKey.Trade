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
  />
</template>
