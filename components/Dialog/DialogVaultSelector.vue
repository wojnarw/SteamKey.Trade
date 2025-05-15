<script setup>
  // From the trade partner
  const props = defineProps({
    userId: {
      type: String,
      required: true
    },
    onlyApps: {
      type: Array,
      default: () => []
    }
  });

  const emit = defineEmits(['submit', 'vaultless']);

  const model = defineModel({
    type: Array,
    default: () => []
  });

  const { decrypt, encrypt } = useVaultSecurity();
  const { user: authUser, password } = toRefs(useAuthStore());
  const validPassword = ref(!!password.value);
  const snackbarStore = useSnackbarStore();
  const supabase = useSupabaseClient();
  const { User, VaultEntry } = useORM();
  const loading = ref(false);

  const { data: user, error: userError } = useLazyAsyncData(`user-${props.userId}`, async () => {
    const user = new User(props.userId);
    await user.load();
    return user.toObject();
  }, {
    getCachedData: (key, nuxtApp) => {
      return nuxtApp.payload.data[key] || nuxtApp.static.data[key];
    }
  });

  watch(() => userError.value, error => {
    if (error) {
      snackbarStore.set('error', 'Failed to load user');
    }
  });

  const internalValue = ref(false);
  const isIncomplete = computed(() => !props.onlyApps.every(appid => {
    const entry = model.value.find(item => item.appId === appid);
    return entry?.vaultEntryId;
  }));
  const missingPartnerVault = computed(() => {
    return user.value && !user.value.publicKey;
  });

  const vaultEntries = ref([]);
  watch([
    () => internalValue.value,
    () => model.value,
    () => validPassword.value
  ], async () => {
    if (!internalValue.value) {
      return;
    }

    if (!validPassword.value) {
      return;
    }

    if (!props.onlyApps.length) {
      return;
    }

    vaultEntries.value = await VaultEntry.getValues(supabase, authUser.value.id, true, props.onlyApps, authUser.value.id);
    vaultEntries.value = await Promise.all(vaultEntries.value.map(async entry => ({
      ...entry,
      value: password.value ? await decrypt(entry.value, password.value) : '********'
    })));

    // remove vault entries that are no longer available
    for (let i = 0; i < model.value.length; i++) {
      const exists = vaultEntries.value.some(entry => entry.id === model.value[i].vaultEntryId);
      if (!exists) {
        model.value[i].vaultEntryId = null;
      }
    }
  }, { immediate: true });

  const submit = async () => {
    if (isIncomplete.value) {
      snackbarStore.set('error', 'Please select a vault entry for each app');
      return;
    }

    if (!user.value.publicKey || !props.userId) {
      snackbarStore.set('error', 'Something went wrong. Please try again later.');
      return;
    }

    loading.value = true;
    try {
      // encrypt selected vault entries
      await Promise.all(model.value.map(async ({ vaultEntryId }) => {
        const entry = vaultEntries.value.find(entry => entry.id === vaultEntryId);
        if (!entry) {
          return;
        }

        const encryptedValue = await encrypt(entry.value, user.value.publicKey);
        const instance = new VaultEntry(vaultEntryId);
        await instance.addValue(user.value.id, encryptedValue);
      }));

      internalValue.value = false;
      emit('submit');
    } finally {
      loading.value = false;
    }
  };
</script>

<template>
  <v-dialog
    v-model="internalValue"
    transition="dialog-center-transition"
    width="500"
  >
    <template #activator="attrs">
      <slot
        name="activator"
        v-bind="attrs"
      />
    </template>
    <v-card :loading="loading">
      <v-card-title class="text-primary">
        Select your vault entries
      </v-card-title>
      <v-card-text class="pa-0">
        <dialog-vault-unlocker @unlocked="validPassword = true" />
        <v-container v-if="validPassword">
          <v-row
            v-for="(item, index) in model"
            :key="item.appId"
          >
            <template v-if="onlyApps.includes(item.appId)">
              <v-col
                class="d-flex align-center"
                cols="12"
                sm="3"
              >
                <nuxt-link
                  class="w-100 h-100"
                  rel="noopener"
                  target="_blank"
                  :to="`/app/${item.appId}`"
                >
                  <v-img
                    v-ripple
                    :alt="`App ${item.appId}`"
                    cover
                    height="56"
                    lazy-src="/applogo.svg"
                    :src="`https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/${item.appId}/header.jpg`"
                  />
                </nuxt-link>
              </v-col>
              <v-col
                cols="12"
                sm="9"
              >
                <v-select
                  v-model="model[index].vaultEntryId"
                  clearable
                  :disabled="missingPartnerVault"
                  hide-details
                  item-title="value"
                  item-value="id"
                  :items="vaultEntries.filter(entry => entry.appId === item.appId)"
                  label="Vault entry"
                >
                  <template #no-data>
                    <v-list-item
                      subtitle="Please add a new vault entry here"
                      target="_blank"
                      title="No vault entries left"
                      :to="`/vault?tab=unsent&appid=${item.appId}&action=add`"
                      @click="internalValue = false"
                    />
                  </template>
                </v-select>
              </v-col>
            </template>
          </v-row>

          <div class="mt-4 text-center">
            <small
              v-if="isIncomplete || missingPartnerVault"
              class="text-warning"
            >
              <v-icon
                icon="mdi-alert-circle-outline"
                start
              />
              {{
                missingPartnerVault
                  ? 'Partner vault not set up. Ask them to, or use the off-platform option.'
                  : 'Incomplete! Please select a vault entry for each app.'
              }}
            </small>
          </div>
        </v-container>
      </v-card-text>
      <v-divider />
      <v-card-actions>
        <v-btn
          variant="text"
          @click="internalValue = false"
        >
          Cancel
        </v-btn>
        <v-spacer />

        <dialog-confirm
          color="warning"
          confirm-text="Confirm"
          title="Exchange off-platform"
          @confirm="emit('vaultless'); internalValue = false"
        >
          <template #activator="attrs">
            <small>
              <a
                href="#"
                v-bind="attrs.props"
              >I prefer to exchange off-platform</a>
            </small>
          </template>

          <template #body>
            <v-alert
              icon="mdi-alert"
              type="warning"
              variant="outlined"
            >
              <p>Are you sure you wish to trade outside of SteamKey.Trade?</p>
              <br>
              <p>Beware that trading off-platform carries a higher risk, as tracking the exchange will not be possible. This can make resolving potential disputes significantly more difficult.</p>
              <br>
              <p>To successfully mark this trade as completed, <b>both parties must acknowledge and agree to do the exchange outside the platform.</b> Communicate this with your trade partner.</p>
            </v-alert>
          </template>
        </dialog-confirm>

        <v-spacer />
        <v-btn
          color="primary"
          :disabled="!validPassword || isIncomplete || loading || missingPartnerVault"
          :loading="loading"
          variant="tonal"
          @click="submit"
        >
          Submit
        </v-btn>
      </v-card-actions>
    </v-card>
  </v-dialog>
</template>