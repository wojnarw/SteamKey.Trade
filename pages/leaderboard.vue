<script setup>
  const { User } = useORM();
  const { isLoggedIn } = storeToRefs(useAuthStore());
  const supabase = useSupabaseClient();

  const title = 'Leaderboard';
  const breadcrumbs = [
    { title: 'Home', to: '/' },
    { title, disabled: true }
  ];

  const mainStat = User.statistics.fields.totalCompletedTrades; // TODO: maybe turn this into a v-select?
  const activeTab = ref('top100');
  const tabs = ['top100', 'friends'];

  const headers = [
    // TODO some values from Users table, how to join? --> can't a view (statistics) cannot use foreign keys
    { title: '#', value: 'rank', sortable: false }, // TODO add position #
    { title: 'User', value: User.statistics.fields.userId, sortable: true },
    { title: User.shortLabels.totalCompletedTrades, value: User.statistics.fields.totalCompletedTrades, sortable: true },
    { title: User.shortLabels.totalAcceptedTrades, value: User.statistics.fields.totalAcceptedTrades, sortable: true },
    { title: User.shortLabels.avgSpeed, value: User.statistics.fields.avgSpeed, sortable: true },
    { title: User.shortLabels.totalReviewsReceived, value: User.statistics.fields.totalReviewsReceived, sortable: true }
  ];

  const queryGetter = () => {
    const query = supabase
      .from(User.statistics.table)
      .select(`
        ${User.statistics.fields.userId},
        ${mainStat},
        ${User.statistics.fields.totalUniqueTrades},
        ${User.statistics.fields.totalDeclinedTrades},
        ${User.statistics.fields.totalAcceptedTrades},
        ${User.statistics.fields.totalReviewsReceived},
        ${User.statistics.fields.avgSpeed}
      `)
      // Exclude top 3 users from the query
      .not(User.statistics.fields.userId, 'in', `(${top3.value.map(user => user.userId)})`);

    // TODO: Implement a friend system (See #94)
    // if (isLoggedIn.value && activeTab.value === 'friends') {
    //   query = query.eq(Trade.fields.receiverId, user.value.id);
    // }

    return query;
  };

  const sortBy = [{
    key: mainStat,
    order: 'desc'
  }];

  const { data: top3, status, error } = useLazyAsyncData(`top-3-${mainStat}`, async () => {
    const { data, error } = await supabase
      .from(User.statistics.table)
      .select(`
        ${User.statistics.fields.userId},
        ${mainStat},
        ${User.statistics.fields.totalUniqueTrades},
        ${User.statistics.fields.totalDeclinedTrades},
        ${User.statistics.fields.totalReviewsReceived},
        ${User.statistics.fields.avgSpeed}
      `)
      .order(mainStat, { ascending: false, nullsFirst: false })
      .order(`${User.statistics.fields.totalUniqueTrades}`, { ascending: false, nullsFirst: false })
      .limit(3);

    if (error) {
      throw error;
    }

    const usersData = data.map(record => User.fromDB(record, User.statistics.fields));
    return usersData;
  });

  watch(error, (value) => {
    if (value) {
      console.error(value);
      throw createError({
        statusCode: 500,
        statusMessage: 'Internal Server Error',
        message: 'An error occurred while loading the leaderboard',
        fatal: true
      });
    }
  });

  useHead({ title });
</script>

<template>
  <s-page-content
    :breadcrumbs="breadcrumbs"
    :loading="status === 'pending'"
  >
    <template
      v-if="isLoggedIn"
      #append
    >
      <!-- friends leaderboard only if logged in-->
      <v-tabs v-model="activeTab">
        <v-tab value="top100">
          <v-icon
            class="mr-2"
            icon="mdi-human-queue"
            variant="tonal"
          />
          Top 100
        </v-tab>
        <v-tab value="friends">
          <v-icon
            class="mr-2"
            icon="mdi-human-male-female"
            variant="tonal"
          />
          Friends
        </v-tab>
      </v-tabs>
    </template>

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
          <v-row justify="center">
            <!-- TODO: Use v-col for responsiveness -->
            <!-- <v-col
              cols="12"
              md="4"
            > -->
            <leaderboard-podium-card
              v-if="top3?.[1]"
              position="2"
              :user="top3[1]"
            />
            <!-- </v-col>
            <v-col
              cols="12"
              md="4"
            > -->
            <leaderboard-podium-card
              v-if="top3?.[0]"
              position="1"
              :user="top3[0]"
            />
            <!-- </v-col>
            <v-col
              cols="12"
              md="4"
            > -->
            <leaderboard-podium-card
              v-if="top3?.[2]"
              position="3"
              :user="top3[2]"
            />
            <!-- </v-col> -->
          </v-row>
          <v-row class="d-flex mt-6">
            <v-card class="d-flex flex-grow-1 flex-column">
              <table-data
                class="h-100"
                :default-sort-by="sortBy"
                :headers="headers"
                no-data-text="No users found"
                :query-getter="queryGetter"
                @click:row="(item) => navigateTo(`/user/${item[User.fields.customUrl] || item[User.fields.steamId]}`)"
              >
                <template #[`item.${User.statistics.fields.userId}`]="{ item }">
                  <rich-profile-link
                    hide-reputation
                    :user-id="item[User.statistics.fields.userId]"
                  />
                </template>
              </table-data>
            </v-card>
          </v-row>
        </v-container>
      </v-window-item>
    </v-window>
  </s-page-content>
</template>
