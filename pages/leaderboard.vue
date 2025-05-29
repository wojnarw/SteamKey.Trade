<script setup>
  import SPageContent from '~/components/SPageContent.vue';
  import PodiumCard from '~/components/Leaderboard/PodiumCard.vue';
  const { User } = useORM();
  const { isLoggedIn } = storeToRefs(useAuthStore());
  const supabase = useSupabaseClient();

  const title = 'Leaderboard';
  const breadcrumbs = [
    { title: 'Home', to: '/' },
    { title, disabled: true }
  ];

  const activeTab = ref('top100');
  const tabs = ['top100', 'friends'];

  const headers = [
    { title: '#', value: 'TODO', sortable: false },
    { title: User.labels.avatar, value: User.fields.avatar, sortable: false },
    { title: User.labels.displayName, value: User.fields.displayName, sortable: true },
    { title: User.labels.region, value: User.fields.region, sortable: true },
    { title: User.labels.createdAt, value: User.fields.createdAt, sortable: true },
    { title: User.labels.completedTrades.title, value: 'completedTrades', sortable: true }, // TODO fields
    { title: User.labels.offersSent.title, value: 'offersSent', sortable: true }
  ];

  const countries = Object.values(User.enums.country).map(cc => ({
    text: User.labels[cc],
    value: cc
  }));

  const filters = [
    { title: User.labels.steamId, value: User.fields.steamId, type: String },
    { title: User.labels.customUrl, value: User.fields.customUrl, type: String },
    { title: User.labels.displayName, value: User.fields.displayName, type: String },
    { title: User.labels.region, value: User.fields.region, type: String, options: countries },
    { title: User.labels.createdAt, value: User.fields.createdAt, type: Date }
  ];

  const attributes = {
    Completed: '80',
    Sent: '55',
    Received: '30',
    Cancelled: '5'
  // [labels.completedTrades.title]: "55",
  // [labels.offersSent.title]: "80",
  // [labels.offersReceived.title]: "30",
  // [labels.offersCancelled.title]: "5",
  };

  const queryGetter = () => {
    return supabase
      .from(User.table)
      .select([User.fields.id, ...headers.map(({ value }) => value)].join(','));
  };

  // TODO: TEMPORARY WE ONLY GET CURRENT USER DATA
  const { user: authUser } = useAuthStore();

  useHead({ title });
</script>

<template>
  <s-page-content :breadcrumbs="breadcrumbs">
    <!-- negative margin so it starts on the same level as breadcrumbs-->
    <div class="mt-n12">
      <!-- friends leaderboard only if logged in-->
      <div
        v-if="isLoggedIn"
        class="d-block w-100"
      >
        <v-tabs
          v-model="activeTab"
          align-tabs="end"
        >
          <v-tab
            class="w-30"
            value="top100"
          >
            <v-icon
              class="mr-2"
              icon="mdi-human-queue"
              variant="tonal"
            />
            Top 100
          </v-tab>
          <v-tab
            class="w-30"
            value="friends"
          >
            <v-icon
              class="mr-2"
              icon="mdi-human-male-female"
              variant="tonal"
            />
            Friends
          </v-tab>
        </v-tabs>
      </div>

      <v-window
        v-model="activeTab"
        class="fill-height"
      >
        <v-window-item
          v-for="tab in tabs"
          :key="tab"
          class="fill-height"
          :value="tab"
        >
          <v-container class="d-flex flex-column align-center my-5">
            <!-- Podium Section -->
            <v-row class="d-flex justify-center overflow-visible">
              <!-- TODO: attributes property with fake data is temporary-->
              <!-- TODO: currently passing just curretn user as prop-->
              <PodiumCard
                :attributes="attributes"
                position="2"
                :user-id="authUser.id"
              />
              <PodiumCard
                :attributes="attributes"
                position="1"
                :user-id="authUser.id"
              />
              <PodiumCard
                :attributes="attributes"
                position="3"
                :user-id="authUser.id"
              />
            </v-row>
          </v-container>

          <v-card class="d-flex flex-grow-1 flex-column">
            <table-data
              class="h-100 "
              :filters="filters"
              filters-in-url
              :headers="headers"
              no-data-text="No users found"
              :query-getter="queryGetter"
              :search-field="User.fields.displayName"
              sort-in-url
              @click:row="(item) => navigateTo(`/user/${item[User.fields.customUrl] || item[User.fields.steamId]}`)"
            >
              <template #[`item.avatar`]="{ item }">
                <v-avatar
                  color="surface-variant"
                  :icon="item.avatar ? undefined : 'mdi-account'"
                  :image="item.avatar ? item.avatar : undefined"
                />
              </template>

              <template #[`item.${User.fields.region}`]="{ item }">
                <span v-tooltip:top="User.labels[item.region]">
                  {{ item.region }}
                </span>
              </template>

              <template #[`item.${User.fields.createdAt}`]="{ item }">
                <rich-date :date="item[User.fields.createdAt]" />
              </template>
            </table-data>
          </v-card>
        </v-window-item>
      </v-window>
    </div>
  </s-page-content>
</template>
