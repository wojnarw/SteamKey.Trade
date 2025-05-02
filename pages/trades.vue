<script setup>
  const { Trade } = useORM();
  const supabase = useSupabaseClient();
  const router = useRouter();
  const route = useRoute();

  const { isLoggedIn, user } = storeToRefs(useAuthStore());
  const activeTab = ref(route.query.tab || 'received');
  const tabs = ['received', 'sent'];

  const headers = computed(() => ([
    { title: Trade.labels.status, value: Trade.fields.status, sortable: true },
    ...(isLoggedIn.value
      ? [
        activeTab.value === 'received'
          ? { title: 'Received from', value: Trade.fields.senderId, sortable: true }
          : { title: 'Sent to', value: Trade.fields.receiverId, sortable: true },
        { title: 'My apps', value: activeTab.value === 'received' ? 'want' : 'have', sortable: false },
        { title: 'Their apps', value: activeTab.value === 'received' ? 'have' : 'want', sortable: false }
      ]
      : [
        { title: Trade.labels.senderId, value: Trade.fields.senderId, sortable: true },
        { title: 'Have', value: 'have', sortable: false },
        { title: Trade.labels.receiverId, value: Trade.fields.receiverId, sortable: true },
        { title: 'Want', value: 'want', sortable: false }
      ]),
    { title: Trade.labels.createdAt, value: Trade.fields.createdAt, sortable: true }
  ]));

  const statuses = Object.values(Trade.enums.status).map(status => ({
    title: Trade.labels[status],
    value: status
  }));
  const filters = computed(() => [
    { title: Trade.labels.status, value: Trade.fields.status, type: String, options: statuses },
    // TODO: Add user search
    ...(isLoggedIn.value && activeTab.value === 'received'
      ? [{ title: Trade.labels.senderId, value: Trade.fields.senderId, type: String }]
      : []),
    { title: Trade.labels.senderDisputed, value: Trade.fields.senderDisputed, type: Boolean },
    { title: Trade.labels.senderTotal, value: Trade.fields.senderTotal, type: Number },
    // TODO: Add user search
    ...(isLoggedIn.value && activeTab.value === 'sent'
      ? [{ title: Trade.labels.receiverId, value: Trade.fields.receiverId, type: String }]
      : []),
    { title: Trade.labels.receiverDisputed, value: Trade.fields.receiverDisputed, type: Boolean },
    { title: Trade.labels.receiverTotal, value: Trade.fields.receiverTotal, type: Number },
    { title: Trade.labels.createdAt, value: Trade.fields.createdAt, type: Date }
  ]);

  const queryGetter = () => {
    let query = supabase
      .from(Trade.table)
      .select(`*, ${Trade.apps.table}(${Trade.apps.fields.appId}, ${Trade.apps.fields.userId})`);

    if (isLoggedIn.value && activeTab.value === 'received') {
      query = query.eq(Trade.fields.receiverId, user.value.id);
    } else if (isLoggedIn.value && activeTab.value === 'sent') {
      query = query.eq(Trade.fields.senderId, user.value.id);
    }

    return query;
  };

  const mapItem = (trade) => {
    const have = trade[Trade.apps.table]
      .filter(app => app[Trade.apps.fields.userId] === trade[Trade.fields.senderId])
      .map(app => app[Trade.apps.fields.appId]);
    const want = trade[Trade.apps.table]
      .filter(app => app[Trade.apps.fields.userId] === trade[Trade.fields.receiverId])
      .map(app => app[Trade.apps.fields.appId]);
    return { ...trade, have, want };
  };

  const breadcrumbs = [
    { title: 'Home', to: '/' },
    { title: 'Trades', disabled: true }
  ];

  // Update URL when tab changes
  watch(() => activeTab.value, (newTab) => {
    if (isLoggedIn.value) {
      router.push({
        query: {
          ...route.query,
          tab: newTab
        }
      });
    }
  });

  // Update active tab when URL changes
  watch(() => route.query, (newQuery) => {
    if (isLoggedIn.value && newQuery.tab && tabs.includes(newQuery.tab) && newQuery.tab !== activeTab.value) {
      activeTab.value = newQuery.tab;
    }
  }, { deep: true });

  useHead({
    title: 'Trades'
  });
</script>

<template>
  <s-page-content :breadcrumbs="breadcrumbs">
    <template #append>
      <v-btn
        v-if="isLoggedIn"
        class="ml-2 bg-surface rounded"
        :icon="$vuetify.display.xs"
        :rounded="$vuetify.display.xs"
        to="/trade/new"
        variant="flat"
      >
        <v-icon
          class="mr-0 mr-sm-2"
          icon="mdi-plus"
        />
        <span class="d-none d-sm-block">
          New trade
        </span>
      </v-btn>
    </template>

    <v-card class="d-flex flex-column h-100">
      <div
        v-if="isLoggedIn"
        class="d-block w-100"
      >
        <v-tabs v-model="activeTab">
          <v-tab
            class="w-50"
            value="received"
          >
            <v-icon
              class="mr-2"
              icon="mdi-arrow-right"
              variant="tonal"
            />
            Received
          </v-tab>
          <v-divider vertical />
          <v-tab
            class="w-50"
            value="sent"
          >
            Sent
            <v-icon
              class="ml-2"
              icon="mdi-arrow-right"
              variant="tonal"
            />
          </v-tab>
        </v-tabs>
        <v-divider />
      </div>

      <v-window
        v-model="activeTab"
        class="flex-grow-1"
        :disabled="!isLoggedIn"
      >
        <v-window-item
          v-for="tab in tabs"
          :key="tab"
          class="fill-height"
          :value="tab"
        >
          <table-data
            class="h-100"
            :default-sort-by="[{
              key: Trade.fields.createdAt,
              order: 'desc'
            }]"
            :filters="filters"
            filters-in-header
            filters-in-url
            :headers="headers"
            :map-item="mapItem"
            :no-data-text="isLoggedIn ? `No ${tab} trades` : 'No trades found'"
            :query-getter="queryGetter"
            @click:row="(item) => navigateTo(`/trade/${item.id}`)"
          >
            <template #[`item.${Trade.fields.status}`]="{ item }">
              <span :class="`text-${Trade.colors[item[Trade.fields.status]]} text-no-wrap`">
                <v-icon
                  class="mt-n1 mr-1"
                  :color="Trade.colors[item[Trade.fields.status]]"
                  :icon="Trade.icons[item[Trade.fields.status]]"
                />
                {{ Trade.labels[item[Trade.fields.status]] }}
              </span>
            </template>

            <template
              v-for="header in [Trade.fields.senderId, Trade.fields.receiverId]"
              :key="header"
              #[`item.${header}`]="{ item }"
            >
              <rich-profile-link :user-id="item[header]" />
            </template>

            <template
              v-for="header in ['have', 'want']"
              :key="header"
              #[`item.${header}`]="{ item }"
            >
              <v-chip color="grey">
                <strong class="text-white">
                  {{ item[header === 'have' ? Trade.fields.senderTotal : Trade.fields.receiverTotal] }}
                </strong>
                <span class="text-grey ml-1">
                  of {{ item[header].length }}
                </span>
                <!-- TODO: Display apps -->
              </v-chip>
            </template>

            <template #[`item.${Trade.fields.createdAt}`]="{ item }">
              <rich-date :date="item[Trade.fields.createdAt]" />
            </template>
          </table-data>
        </v-window-item>
      </v-window>
    </v-card>
  </s-page-content>
</template>