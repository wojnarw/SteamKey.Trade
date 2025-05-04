<script setup>
  const { isLoggedIn } = storeToRefs(useAuthStore());

  const activityTitle = computed(() => {
    return `${isLoggedIn.value ? 'My ' : ''}Trade Activity`;
  });
</script>

<template>
  <TradeActivity
    class="h-100"
    :limit="10"
    :show-trade-links="true"
    :title="activityTitle"
    title-center
  />
</template>

<style lang="scss" scoped>
  .activity-info {
    font-size: 0.65rem;
    color: #888;
  }

  .activity-body {
    color: white;
    font-size: 1rem;
    word-wrap: break-word;
  }
</style>
