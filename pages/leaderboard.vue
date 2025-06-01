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
    // { title: '#', value: 'TODO', sortable: false },
    // { title: User.labels.avatar, value: User.fields.avatar, sortable: false },
    { title: User.statistics.fields.userId, value: User.statistics.fields.userId, sortable: true },
    // { title: User.labels.region, value: User.fields.region, sortable: true },
    { title: User.statistics.fields.totalCompletedTrades.title, value: User.statistics.fields.totalCompletedTrades, sortable: true },
    { title: User.statistics.fields.totalAcceptedTrades.title, value: User.statistics.fields.totalAcceptedTrades, sortable: true }
    // { title: User.labels.createdAt, value: User.fields.createdAt, sortable: true }
  ];

  const countries = Object.values(User.enums.country).map(cc => ({
    text: User.labels[cc],
    value: cc
  }));

  const filters = [
    { title: User.labels.steamId, value: User.fields.steamId, type: String },
    { title: User.labels.customUrl, value: User.fields.customUrl, type: String },
    // { title: User.labels.displayName, value: User.fields.displayName, type: String },
    { title: User.labels.region, value: User.fields.region, type: String, options: countries },
    { title: User.labels.createdAt, value: User.fields.createdAt, type: Date }
  ];

  // const queryGetter = () => {
  //   console.info('WW:queryGetter START');
  //   const result = supabase
  //     .from(User.table)
  //     .select([User.fields.id, ...headers.map(({ value }) => value)].join(','));
  //   console.info(result);
  //   return result;
  // };

  const { table: userStatsTable, fields: userStatsFields } = User.statistics;
  const mainStat = userStatsFields.totalCompletedTrades; // maybe turn this into a v-select?
  // console.info('mainStat: ' + mainStat);

  // const queryGetter = () => {
  //   const result = supabase.from(userStatsTable)
  //     .select(`${userStatsFields.userId},${mainStat}, ${userStatsFields.totalUniqueTrades}, ${userStatsFields.totalDeclinedTrades},
  //     ${userStatsFields.totalReviewsReceived}, ${userStatsFields.avgSpeed}`)
  //     .order(mainStat, { ascending: false, nullsFirst: false })
  //     .order(mainStat, { ascending: false, nullsFirst: false })
  //     .limit(10);
  //
  //   if (error) {
  //     throw error;
  //   }
  //   console.info(result);
  //   return result;
  // };
  const queryGetter = () => {
    const query = supabase
      .from(userStatsTable)
      .select(`${userStatsFields.userId},${mainStat}, ${userStatsFields.totalUniqueTrades}, ${userStatsFields.totalDeclinedTrades}, ${userStatsFields.totalReviewsReceived}, ${userStatsFields.avgSpeed}`);

    // if (isLoggedIn.value && activeTab.value === 'friends') {
    //   query = query.eq(Trade.fields.receiverId, user.value.id);
    // } else if (isLoggedIn.value && activeTab.value === 'sent') {
    //   query = query.eq(Trade.fields.senderId, user.value.id);
    // }
    console.warn(query);
    return query;
  };

  // const sortBy = [{
  //   key: mainStat,
  //   order: 'desc'
  // }];

  const { data: top3, status, error } = useLazyAsyncData(`top-3-${mainStat}`, async () => {
    const { data, error } = await supabase
      .from(userStatsTable)
      .select(`${userStatsFields.userId},${mainStat}, ${userStatsFields.totalUniqueTrades}, ${userStatsFields.totalDeclinedTrades},
      ${userStatsFields.totalReviewsReceived}, ${userStatsFields.avgSpeed}`)
      .order(mainStat, { ascending: false, nullsFirst: false })
      // .order(`${userStatsFields.totalUniqueTrades}`, { ascending: false, nullsFirst: false })
      .limit(10);

    if (error) {
      throw error;
    }

    const usersData = data.map(record => User.fromDB(record, userStatsFields));
    // console.info('WW:usr ' + JSON.stringify(usersData));
    return usersData;
  });

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
        class=""
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
              <PodiumCard
                v-if="top3?.[1]"
                position="2"
                :user="top3[1]"
              />
              <PodiumCard
                v-if="top3?.[0]"
                position="1"
                :user="top3[0]"
              />
              <PodiumCard
                v-if="top3?.[2]"
                position="2"
                :user="top3[2]"
              />
            </v-row>
            <v-row class="d-flex">
              <v-card class="d-flex flex-grow-1 flex-column">
                <!--                <table-data-->
                <!--                  :headers="headers"-->
                <!--                  no-data-text="No users found"-->
                <!--                  :query-getter="queryGetter"-->
                <!--                  sort-in-url-->
                <!--                />-->
                <table-data
                  class="h-100 "
                  :filters="filters"
                  filters-in-url
                  :headers="headers"
                  no-data-text="No users found"
                  :query-getter="queryGetter"
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
            </v-row>
          </v-container>
        </v-window-item>
      </v-window>
    </div>
  </s-page-content>
</template>
