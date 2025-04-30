<script setup>
  const title = 'Apps';
  const breadcrumbs = [
    { title: 'Home', to: '/' },
    { title, disabled: true }
  ];

  const { App } = useORM();
  const { facets } = storeToRefs(useAppsStore());
  const appTypes = Object.entries(App.enums.type).map(([key, value]) => ({ title: App.labels[key], value }));
  const filters = computed(() => ([
    { title: App.labels.id, value: App.fields.id, type: Number },
    { title: App.labels.changeNumber, value: App.fields.changeNumber, type: Number },
    { title: App.labels.parentId, value: App.fields.parentId, type: Number },
    { title: App.labels.type, value: App.fields.type, type: String, options: appTypes },
    { title: App.labels.description, value: App.fields.description, type: String },
    { title: App.labels.developers, value: App.fields.developers, type: Array, options: facets.value?.developers },
    { title: App.labels.publishers, value: App.fields.publishers, type: Array, options: facets.value?.publishers },
    { title: App.labels.tags, value: App.fields.tags, type: Array, options: facets.value?.tags },
    { title: App.labels.languages, value: App.fields.languages, type: Array, options: facets.value?.languages },
    { title: App.labels.platforms, value: App.fields.platforms, type: Array, options: facets.value?.platforms },
    { title: App.labels.free, value: App.fields.free, type: Boolean },
    { title: App.labels.plusOne, value: App.fields.plusOne, type: Boolean },
    { title: App.labels.exfgls, value: App.fields.exfgls, type: Boolean },
    { title: App.labels.steamdeck, value: App.fields.steamdeck, type: Boolean },
    { title: App.labels.positiveReviews, value: App.fields.positiveReviews, type: Number },
    { title: App.labels.negativeReviews, value: App.fields.negativeReviews, type: Number },
    { title: App.labels.cards, value: App.fields.cards, type: Number },
    { title: App.labels.achievements, value: App.fields.achievements, type: Number },
    { title: App.labels.bundles, value: App.fields.bundles, type: Number },
    { title: App.labels.giveaways, value: App.fields.giveaways, type: Number },
    { title: App.labels.libraries, value: App.fields.libraries, type: Number },
    { title: App.labels.wishlists, value: App.fields.wishlists, type: Number },
    { title: App.labels.tradelists, value: App.fields.tradelists, type: Number },
    { title: App.labels.blacklists, value: App.fields.blacklists, type: Number },
    { title: App.labels.steamPackages, value: App.fields.steamPackages, type: Number },
    { title: App.labels.steamBundles, value: App.fields.steamBundles, type: Number },
    { title: App.labels.retailPrice, value: App.fields.retailPrice, type: Number },
    { title: App.labels.discountedPrice, value: App.fields.discountedPrice, type: Number },
    { title: App.labels.marketPrice, value: App.fields.marketPrice, type: Number },
    { title: App.labels.historicalLow, value: App.fields.historicalLow, type: Number },
    { title: App.labels.removedAs, value: App.fields.removedAs, type: String, options: facets.value?.removedAs },
    { title: App.labels.removedAt, value: App.fields.removedAt, type: String },
    { title: App.labels.releasedAt, value: App.fields.releasedAt, type: Date },
    { title: App.labels.updatedAt, value: App.fields.updatedAt, type: Date },
    { title: App.labels.createdAt, value: App.fields.createdAt, type: Date }
  ]));

  useHead({ title });
</script>

<template>
  <s-page-content :breadcrumbs="breadcrumbs">
    <v-card class="d-flex fill-height pa-2">
      <table-apps :filters="filters" />
    </v-card>
  </s-page-content>
</template>