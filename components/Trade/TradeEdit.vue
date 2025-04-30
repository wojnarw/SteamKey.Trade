<script setup>
  const props = defineProps({
    id: {
      type: String,
      default: null
    },
    counterId: {
      type: String,
      default: null
    },
    copyId: {
      type: String,
      default: null
    },
    sender: {
      type: String,
      default: null
    },
    receiver: {
      type: String,
      default: null
    }
  });

  const { user } = useAuthStore();
  const { App, Trade, Collection } = useORM();
  const snackbarStore = useSnackbarStore();
  const router = useRouter();
  const supabase = useSupabaseClient();

  const sides = ['sender', 'receiver'];
  const currentSide = ref(sides[0]);
  const valid = ref(false);
  const isNew = !props.id;
  const isCounter = !!props.counterId;
  const isCopy = !!props.copyId;

  let tradeKey = 'trade';
  let appsKey = 'trade-apps';
  if (props.id) {
    tradeKey = `trade-${props.id}`;
    appsKey = `trade-apps-${props.id}`;
  } else if (props.copyId) {
    tradeKey = `trade-copy-${props.copyId}`;
    appsKey = `trade-apps-copy-${props.copyId}`;
  } else if (props.counterId) {
    tradeKey = `trade-counter-${props.counterId}`;
    appsKey = `trade-apps-counter-${props.counterId}`;
  } else if (isNew) {
    tradeKey = 'trade-new';
    appsKey = 'trade-apps-new';
  }

  const { data: trade, status: tradeStatus, error: tradeError } = useLazyAsyncData(tradeKey, async () => {
    const id = props.id || props.counterId || props.copyId;
    const instance = new Trade(id);
    if (!isNew) {
      try {
        await instance.load();
      } catch (err) {
        if (err.code === 'PGRST116') {
          let message = 'The trade you are looking for does not exist';
          if (isCounter) {
            message = 'The trade you are trying to counter does not exist';
          } else if (isCopy) {
            message = 'The trade you are trying to copy does not exist';
          }

          throw createError({
            statusCode: 404,
            statusMessage: 'Trade not found',
            message,
            fatal: true
          });
        }

        throw err;
      }
    }

    const data = instance.toObject();

    if (isCounter) {
      data.id = null;
      data.originalId = id;
      data.status = Trade.enums.status.pending;

      const {
        senderId,
        senderDisputed,
        senderVaultless,
        senderTotal,
        receiverId,
        receiverDisputed,
        receiverVaultless,
        receiverTotal
      } = data;

      data.senderId = receiverId;
      data.senderDisputed = receiverDisputed;
      data.senderVaultless = receiverVaultless;
      data.senderTotal = receiverTotal;
      data.receiverId = senderId;
      data.receiverDisputed = senderDisputed;
      data.receiverVaultless = senderVaultless;
      data.receiverTotal = senderTotal;
    } else if (isCopy) {
      data.originalId = id;
      data.id = null;
      data.status = Trade.enums.status.pending;
    }

    if (data.senderId !== user.id && (isCounter || isCopy)) {
      const action = isCounter ? 'counter' : 'copy';
      throw createError({
        statusCode: 403,
        statusMessage: 'Forbidden',
        message: `You are not allowed to ${action} this trade`,
        fatal: true
      });
    }

    data.senderId = props.sender || user.id;
    data.receiverId = props.receiver || data.receiverId;
    return data;
  });

  const { data: tradeApps, status: appsStatus, error: appsError } = useLazyAsyncData(appsKey, async () => {
    if (isNew && !isCounter && !isCopy) {
      return { sender: [], receiver: [] };
    }

    const id = props.id || props.counterId || props.copyId;
    const instance = new Trade(id);
    const apps = await instance.getApps(true);

    return {
      sender: apps.filter(app => app.trade[isCounter ? 'receiverId' : 'senderId'] === app.userId),
      receiver: apps.filter(app => app.trade[isCounter ? 'senderId' : 'receiverId'] === app.userId)
    };
  });

  watch(() => tradeError.value || appsError.value, (error) => {
    if (error) {
      console.error(error);
      throw error;
    }
  });

  const users = ref({ sender: props.sender || user.id, receiver: props.receiver });
  const selectedCollections = ref({ sender: null, receiver: null });
  const selectedApps = ref({ sender: [], receiver: [] });
  const mandatoryApps = ref({ sender: [], receiver: [] });

  // If apps are connected to a vault entry, headless mode is enabled
  const headless = ref(false);

  watch(() => trade.value, () => {
    if (!trade.value) {
      return;
    }

    users.value.sender = trade.value.senderId;
    users.value.receiver = trade.value.receiverId;
  }, { deep: true, immediate: true });

  watch(() => tradeApps.value, () => {
    if (tradeApps.value && tradeApps.value.sender && tradeApps.value.receiver && (isCopy || isCounter)) {
      headless.value = tradeApps.value.sender.every(app => app.vaultEntryId);

      selectedCollections.value.sender = tradeApps.value.sender.map(app => app.collectionId).filter((id, index, self) => self.indexOf(id) === index);
      selectedCollections.value.receiver = tradeApps.value.receiver.map(app => app.collectionId).filter((id, index, self) => self.indexOf(id) === index);

      const appids = [...tradeApps.value.sender, ...tradeApps.value.receiver]
        .map(app => app.appId)
        .filter((appId, index, self) => appId && self.indexOf(appId) === index);
      if (!appids.length) {
        return;
      }

      App.query(supabase, [
        { filter: 'in', params: [App.fields.id, appids] }
      ]).then(instances => {
        const data = instances.map(instance => instance.toObject());
        selectedApps.value.sender = data.filter(app => tradeApps.value.sender.some(({ appId }) => appId === app.id));
        selectedApps.value.receiver = data.filter(app => tradeApps.value.receiver.some(({ appId }) => appId === app.id));
        mandatoryApps.value.sender = data.filter(app => tradeApps.value.sender.some(({ appId, mandatory }) => appId === app.id && mandatory));
        mandatoryApps.value.receiver = data.filter(app => tradeApps.value.receiver.some(({ appId, mandatory }) => appId === app.id && mandatory));
      });
    }
  }, { deep: true, immediate: true });

  watch(() => selectedApps.value, () => {
    trade.value.senderTotal = Math.max(Math.min(selectedApps.value.sender.length, trade.value.senderTotal), mandatoryApps.value.sender.length);
    trade.value.receiverTotal = Math.max(Math.min(selectedApps.value.receiver.length, trade.value.receiverTotal), mandatoryApps.value.receiver.length);

    for (const side of sides) {
      const apps = [];
      for (const app of selectedApps.value[side]) {
        const existingTradeApp = tradeApps.value[side].find(tradeApp => tradeApp.appId === app.id) || {};
        apps.push({
          appId: app.id,
          collectionId: existingTradeApp.collectionId || app.collection.collectionId || null,
          vaultEntryId: existingTradeApp.vaultEntryId || null,
          userId: side === 'sender' ? users.value.sender : users.value.receiver,
          mandatory: mandatoryApps.value[side].some(({ id }) => id === app.id),
          selected: false
        });
      }
      tradeApps.value[side] = apps;
    }
  }, { deep: true });

  watch(() => users.value, async () => {
    if (users.value.sender === users.value.receiver) {
      snackbarStore.set('warning', 'You cannot trade with yourself');
      users.value.receiver = null;
      return;
    }

    if (isNew && !isCounter && !isCopy) {
      if (users.value.sender) {
        // Set default sender collection to the user's master tradelist
        const masterTradelist = await Collection.getMasterTradelist(supabase, users.value.sender);
        selectedCollections.value.sender = [masterTradelist.id];
      } else {
        selectedCollections.value.sender = null;
      }

      if (users.value.receiver) {
        // Set default receiver collection to the user's master tradelist
        const masterTradelist = await Collection.getMasterTradelist(supabase, users.value.receiver);
        selectedCollections.value.receiver = [masterTradelist.id];
      } else {
        selectedCollections.value.receiver = null;
      }
    }

    if (users.value.sender !== trade.value.senderId) {
      trade.value.senderId = users.value.sender;
    }
    if (users.value.receiver !== trade.value.receiverId) {
      trade.value.receiverId = users.value.receiver;
    }
  }, { deep: true, immediate: true });

  const isValid = computed(() => {
    return !!(valid.value
      && selectedApps.value.sender.length
      && trade.value.senderTotal
      && selectedApps.value.sender.length >= trade.value.senderTotal
      && mandatoryApps.value.sender.length <= trade.value.senderTotal
      && selectedApps.value.receiver.length
      && trade.value.receiverTotal
      && selectedApps.value.receiver.length >= trade.value.receiverTotal
      && mandatoryApps.value.receiver.length <= trade.value.receiverTotal
    );
  });

  const isLoading = computed(() => {
    return tradeStatus.value === 'pending' || appsStatus.value === 'pending';
  });

  const submit = async () => {
    if (!isValid.value) {
      snackbarStore.set('warning', 'Trade offer is incomplete');
      return;
    }

    try {
      trade.value.status = Trade.enums.status.pending;

      const instance = new Trade(trade.value.id);
      Object.assign(instance, trade.value);
      instance.senderId = users.value.sender;
      instance.receiverId = users.value.receiver;

      const savedInstance = await instance.save();

      await savedInstance.setApps(Object.values(tradeApps.value).flat(), false, true);

      // decline original trade if countered
      if (props.counterId && trade.value.originalId) {
        const originalTrade = new Trade(trade.value.originalId);
        await originalTrade.decline();
      }

      snackbarStore.set('success', isNew ? 'Trade sent' : 'Trade saved');
      await navigateTo(`/trade/${savedInstance.id}`);
    } catch (error) {
      snackbarStore.set('error', error.message);
    }
  };

  const title = isNew ? 'New trade' : 'Editing trade';
  const breadcrumbs = [
    { title: 'Home', to: '/' },
    { title: 'Trades', to: '/trades' },
    { title: isNew ? 'New' : 'Edit', disabled: true }
  ];

  useHead({ title });

  // Calculate square grid values for trade apps display
  const getGridStyle = (count) => {
    if (!count) { return {}; }

    // Calculate the number of columns to make a square grid
    const columns = Math.ceil(Math.sqrt(count));

    return {
      'grid-template-columns': `repeat(${columns}, 1fr)`,
      'grid-template-rows': `repeat(${Math.ceil(count / columns)}, 1fr)`
    };
  };
</script>

<template>
  <s-page-content
    :breadcrumbs="breadcrumbs"
    :loading="isLoading"
  >
    <v-form
      v-model="valid"
      class="d-flex flex-column flex-grow-1"
      @submit.prevent="submit"
    >
      <v-row>
        <v-col
          cols="12"
          lg="8"
          order="2"
          order-lg="1"
        >
          <v-card class="d-flex flex-column fill-height">
            <div class="d-block">
              <v-tabs
                v-model="currentSide"
                class="tabs"
              >
                <template
                  v-for="tab in sides"
                  :key="tab"
                >
                  <v-tab
                    class="w-50"
                    :disabled="currentSide === tab || !users[tab]"
                    :value="tab"
                  >
                    <v-hover>
                      <template #default="{ isHovering, props: hoverProps }">
                        <div style="position: relative">
                          <rich-profile-link
                            v-if="users[tab]"
                            :key="users[tab]"
                            hide-reputation
                            no-link
                            :style="{ pointerEvents: 'none' }"
                            :user-id="users[tab]"
                          />
                          <dialog-select-user
                            v-if="tab !== 'sender'"
                            :title="`${users[tab] ? 'Change' : 'Select'} trade ${Trade.labels[tab].toLowerCase()}`"
                            @select:user="userId => users[tab] = userId"
                          >
                            <template #activator="{ props: dialogProps }">
                              <v-btn
                                v-bind="{ ...hoverProps, ...dialogProps }"
                                icon
                                size="x-small"
                                :style="users[tab] ? 'left: 1px; top: -1px; position: absolute;' : 'margin-right: 8px;'"
                                :variant="isHovering ? 'tonal' : 'text'"
                              >
                                <v-icon
                                  v-if="isHovering || !users[tab]"
                                  :class="!isHovering && tab === 'to' ? 'flipped' : ''"
                                  :icon="isHovering ? 'mdi-pencil' : tab === 'from' ? 'mdi-account-arrow-right' : 'mdi-account-arrow-left'"
                                  size="x-large"
                                />
                              </v-btn>
                              <span v-if="!users[tab]">Select a trader</span>
                            </template>
                          </dialog-select-user>
                        </div>
                      </template>
                    </v-hover>
                  </v-tab>

                  <v-divider
                    v-if="tab !== sides[sides.length - 1]"
                    vertical
                  />
                </template>
              </v-tabs>
              <v-divider />
            </div>
            <v-window
              v-model="currentSide"
              class="fill-height"
            >
              <v-window-item
                v-for="tab in sides"
                :key="tab"
                class="fill-height"
                :value="tab"
              >
                <v-container class="d-flex flex-column fill-height">
                  <dialog-select-collection
                    v-if="users[tab]"
                    multiple
                    :table-props="{
                      showSelect: true,
                      onlyUsers: [users[tab]],
                      onlyTypes: [Collection.enums.type.tradelist]
                    }"
                    @select="items => selectedCollections[tab] = items.map(({ id }) => id)"
                  >
                    <template #activator="{ props: dialogProps }">
                      <v-btn
                        v-bind="dialogProps"
                        block
                        class="flex-grow-0"
                        variant="tonal"
                      >
                        <v-icon
                          icon="mdi-pencil"
                          start
                        />
                        Tradelist selection
                      </v-btn>
                    </template>
                  </dialog-select-collection>

                  <table-apps
                    v-if="selectedCollections[tab]"
                    v-model="selectedApps[tab]"
                    v-model:mandatory="mandatoryApps[tab]"
                    class="flex-grow-1"
                    :only-collections="selectedCollections[tab]"
                    show-select
                  />
                </v-container>
              </v-window-item>
            </v-window>
          </v-card>
        </v-col>
        <v-col
          class="d-flex flex-column"
          cols="12"
          lg="4"
          order="1"
          order-lg="2"
          style="gap: 1.5em;"
        >
          <chat-container
            v-if="id"
            :trade-id="id"
          />

          <v-card class="d-flex flex-column flex-grow-1 h-100">
            <v-card-title class="text-button">
              <v-icon
                icon="mdi-information"
                start
              />
              Ratio & summary
            </v-card-title>

            <v-divider />

            <v-card-text class="d-flex flex-column flex-grow-1">
              <v-row class="pa-4">
                <v-col
                  v-for="side in sides"
                  :key="`summary-${side}`"
                  class="d-flex flex-wrap justify-center  pt-0"
                  cols="5"
                  :order="side === 'sender' ? 1 : 3"
                >
                  <div
                    v-if="!selectedApps[side].length"
                    class="d-flex flex-column justify-center align-center text-center"
                  >
                    <span class="text-disabled font-italic">Select apps to trade</span>
                  </div>
                  <div
                    v-else
                    class="d-flex flex-column flex-grow-1 "
                  >
                    <v-slider
                      v-model.number="trade[side === 'sender' ? 'senderTotal' : 'receiverTotal']"
                      class="w-100 mb-2 flex-grow-0"
                      :disabled="selectedApps[side].every(({ id }) => mandatoryApps[side].some(({ id: mandatoryId }) => mandatoryId === id))"
                      hide-details
                      :max="selectedApps[side].length"
                      :min="mandatoryApps[side].length"
                      required
                      step="1"
                      type="number"
                      variant="plain"
                    />
                    <div
                      class="flex-grow-1 app-grid"
                      :style="getGridStyle(selectedApps[side].length)"
                    >
                      <nuxt-link
                        v-for="app in selectedApps[side]"
                        :key="`summary-${app.id}`"
                        class="app-grid-item"
                        rel="noopener"
                        target="_blank"
                        :to="`/app/${app.id}`"
                      >
                        <v-img
                          v-ripple
                          v-tooltip:top="app.title"
                          :alt="app.title"
                          aspect-ratio="1"
                          class="h-100 w-100"
                          cover
                          lazy-src="/applogo.svg"
                          :src="app.header || `https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps/${app.id}/header.jpg`"
                        />
                      </nuxt-link>
                    </div>
                  </div>
                </v-col>
                <v-col
                  class="d-flex flex-column justify-center align-center"
                  cols="2"
                  order="2"
                >
                  <v-icon
                    class="mx-4"
                    color="primary"
                    icon="mdi-swap-horizontal"
                    size="32"
                  />
                </v-col>
              </v-row>
              <div class="text-center mt-4">
                {{ trade.senderTotal || 0 }} of {{ selectedApps.sender.length || 0 }} apps, in exchange for {{ trade.receiverTotal || 0 }} of {{ selectedApps.receiver.length || 0 }} apps
              </div>
            </v-card-text>
          </v-card>
        </v-col>
      </v-row>

      <v-footer
        class="mt-6 flex-grow-0"
        rounded
      >
        <v-btn
          variant="text"
          @click="router.back"
        >
          Cancel
        </v-btn>
        <v-spacer />
        <div class="d-flex flex-row align-center h-100">
          <v-switch
            v-model="headless"
            :color="headless ? 'warning' : undefined"
            hide-details
            true-icon="mdi-exclamation-thick"
          >
            <template #label>
              <span class="d-sm-block d-none">Auto-complete</span>

              <v-icon
                v-tooltip:left="'Ensures all offered apps are connected to a vault entry,\nand automatically completes the trade when accepted'"
                end
                icon="mdi-information-outline"
                size="20"
              />
            </template>
          </v-switch>
          <v-btn
            v-if="!headless || !trade.receiverId"
            class="ml-4"
            color="success"
            :disabled="!isValid"
            type="submit"
            variant="tonal"
          >
            {{ isNew ? 'Send' : 'Save' }}
          </v-btn>
          <dialog-vault-selector
            v-else
            v-model="tradeApps.sender"
            :only-apps="selectedApps.sender.map(({ id }) => id)"
            :user-id="trade.receiverId"
            @submit="submit"
            @vaultless="trade.senderVaultless = true; submit()"
          >
            <template #activator="attrs">
              <v-btn
                v-bind="attrs.props"
                class="ml-4"
                color="success"
                :disabled="!isValid"
                variant="tonal"
              >
                {{ isNew ? 'Send' : 'Save' }}
              </v-btn>
            </template>
          </dialog-vault-selector>
        </div>
      </v-footer>
    </v-form>
  </s-page-content>
</template>

<style lang="scss" scoped>
  .flipped {
    transform: scaleX(-1);
  }

  .tabs {
    ::v-deep(.v-btn--disabled) {
      opacity: inherit;
      pointer-events: inherit;
    }
  }

  .app-grid {
    display: grid;
    grid-gap: 8px;
    width: 100%;
    height: 100%;

    .app-grid-item {
      aspect-ratio: 1;
      display: block;
    }
  }
</style>