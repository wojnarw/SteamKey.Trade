<script setup>
  const { Collection } = useORM();

  const internalValue = ref(false);

  const { sync: syncWishlist, loading: loadingWishlist } = useSteamSync(Collection.enums.type.wishlist);
  const { sync: syncLibrary, loading: loadingLibrary } = useSteamSync(Collection.enums.type.library);

  const loading = computed(() => loadingWishlist.value || loadingLibrary.value);
</script>

<template>
  <v-dialog
    v-model="internalValue"
    width="500"
  >
    <template #activator="attrs">
      <slot
        name="activator"
        v-bind="attrs"
      />
    </template>
    <v-card :loading="loading">
      <v-card-title>
        Synchronize Master Collections
      </v-card-title>
      <v-card-text>
        <v-btn
          block
          :disabled="loadingLibrary"
          :loading="loadingWishlist"
          variant="tonal"
          @click="syncWishlist"
        >
          <v-icon
            class="mr-2"
            icon="mdi-sync"
          />
          Sync with Steam Wishlist
        </v-btn>

        <v-btn
          block
          class="mt-4"
          :disabled="loadingWishlist"
          :loading="loadingLibrary"
          variant="tonal"
          @click="syncLibrary"
        >
          <v-icon
            class="mr-2"
            icon="mdi-sync"
          />
          Sync with Steam Library
        </v-btn>
      </v-card-text>
      <v-divider />
      <v-card-actions>
        <v-btn
          variant="text"
          @click="internalValue = false"
        >
          Cancel
        </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>