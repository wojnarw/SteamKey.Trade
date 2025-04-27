<script setup>
  defineProps({
    loading: {
      type: Boolean,
      default: false
    },
    breadcrumbs: {
      type: Array,
      default: () => []
    }
  });
</script>

<template>
  <v-container
    v-if="loading"
    class="d-flex flex-column flex-grow-1 h-100"
  >
    <div>
      <v-skeleton-loader
        class="bg-transparent ml-n4"
        loading
        :type="`chip@${breadcrumbs.length}`"
      />
    </div>
    <v-card class="rounded-lg flex-grow-1 d-flex">
      <div class="v-skeleton-loader flex-grow-1 d-flex">
        <div class="v-skeleton-loader__bone v-skeleton-loader__ossein h-100 opacity-50" />
      </div>
    </v-card>
  </v-container>
  <v-container
    v-else
    class="d-flex flex-column flex-grow-1 h-100"
  >
    <div class="d-flex align-center justify-space-between">
      <v-breadcrumbs
        v-if="breadcrumbs?.length"
        :items="breadcrumbs"
      />

      <div>
        <slot name="append" />
      </div>
    </div>

    <slot name="default" />
  </v-container>
</template>