<script setup>
  import { FunctionsHttpError } from '@supabase/supabase-js';

  const supabase = useSupabaseClient();
  const snackbarStore = useSnackbarStore();
  const { user, updateUserCollections } = useAuthStore();
  const internalValue = ref(false);

  const steamWishlistSyncing = ref(false);
  const syncSteamWishlist = async () => {
    steamWishlistSyncing.value = true;
    try {
      const { data, error } = await supabase.functions.invoke('steam-sync', {
        body: {
          userId: user.id,
          type: 'wishlist'
        }
      });

      if (error) {
        throw error;
      }

      await updateUserCollections();

      snackbarStore.set('success', 'Steam Wishlist synchronized');

      await navigateTo(`/collection/${data.wishlist}`);
    } catch (error) {
      console.error(error);
      if (error instanceof FunctionsHttpError) {
        const message = await error.context.json();
        snackbarStore.set('error', message.error || message);
      } else {
        snackbarStore.set('error', 'An unknown error occurred while synchronizing the Steam Wishlist');
      }
    }
    steamWishlistSyncing.value = false;
  };

  const steamLibrarySyncing = ref(false);
  const syncSteamLibrary = async () => {
    steamLibrarySyncing.value = true;
    try {
      const { data, error } = await supabase.functions.invoke('steam-sync', {
        body: {
          userId: user.id,
          type: 'library'
        }
      });

      if (error) {
        throw error;
      }

      await updateUserCollections();

      snackbarStore.set('success', 'Steam Library synchronized');

      await navigateTo(`/collection/${data.library}`);
    } catch (error) {
      console.error(error);
      if (error instanceof FunctionsHttpError) {
        const message = await error.context.json();
        snackbarStore.set('error', message.error || message);
      } else {
        snackbarStore.set('error', 'An unknown error occurred while synchronizing the Steam Library');
      }
    }
    steamLibrarySyncing.value = false;
  };

  const loading = computed(() => steamWishlistSyncing.value || steamLibrarySyncing.value);
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
          :disabled="steamLibrarySyncing"
          :loading="steamWishlistSyncing"
          variant="tonal"
          @click="syncSteamWishlist"
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
          :disabled="steamWishlistSyncing"
          :loading="steamLibrarySyncing"
          variant="tonal"
          @click="syncSteamLibrary"
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