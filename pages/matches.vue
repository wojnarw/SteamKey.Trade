<script setup>
  const { User, Collection } = useORM();

  const snackbarStore = useSnackbarStore();
  const { user: authUser } = useAuthStore();
  const supabase = useSupabaseClient();

  const singleUser = ref(false);
  const selectedUser = useSearchParam('user', null);

  const singleApp = ref(false);
  const selectedApp = useSearchParam('app', null);

  // Match filtering option
  const matchFilterOptions = [
    { value: 'all', title: 'Everything' },
    { value: 'oneSide', title: 'Onsided matches' },
    { value: 'bothSides', title: 'Mutual matches' }
  ];
  const matchFilter = ref('oneSide'); // Default to one side matching apps

  const loading = ref(false);
  const matches = ref([]);
  const userPage = ref(1);
  const batchSize = 10;
  const hasMoreUsers = ref(true);
  const processedUsers = ref(new Set());

  const reset = () => {
    matches.value = [];
    userPage.value = 1;
    hasMoreUsers.value = true;
    processedUsers.value.clear();
  };

  // When user or app is set in URL, infer single mode
  watch([selectedUser, selectedApp], ([newUser, newApp]) => {
    const isSingleUser = newUser !== null;
    if (singleUser.value !== isSingleUser) {
      singleUser.value = isSingleUser;
    }
    const isSingleApp = newApp !== null;
    if (singleApp.value !== isSingleApp) {
      singleApp.value = isSingleApp;
    }
  }, { immediate: true });
  // When user or app is set in URL, update selected values
  watch([singleUser, singleApp], ([newSingleUser, newSingleApp]) => {
    if (!newSingleUser) {
      selectedUser.value = null;
    }
    if (!newSingleApp) {
      selectedApp.value = null;
    }
  }, { immediate: true });

  // Function to get user collection apps to match against
  const getCollectionApps = async (users) => {
    const results = {};

    // Get auth user's master collections apps (tradelist, wishlist)
    const authUserApps = await Collection.getMasterCollectionsApps(supabase, authUser.id);
    results[authUser.id] = {
      tradelist: authUserApps?.tradelist || [],
      wishlist: authUserApps?.wishlist || []
    };

    // Get selected or all users' master collections apps
    for (const userId of users) {
      if (userId === authUser.id) { continue; }

      try {
        const userApps = await Collection.getMasterCollectionsApps(supabase, userId);
        if (userApps) {
          results[userId] = {
            tradelist: userApps.tradelist || [],
            wishlist: userApps.wishlist || []
          };
        }
      } catch (error) {
        console.error(`Error fetching collections for user ${userId}:`, error);
      }
    }

    return results;
  };

  // Get users to match against in batches
  const getUsers = async () => {
    const userIds = [];

    if (singleUser.value) {
      userIds.push(selectedUser.value);
      hasMoreUsers.value = false;
    } else {
      // Fetch active users in batches for infinite scrolling
      const { data, error } = await supabase
        .from(User.table)
        .select(User.fields.id)
        .neq(User.fields.id, authUser.id)
        .order('updated_at', { ascending: false }) // most recently active first
        .range((userPage.value - 1) * batchSize, userPage.value * batchSize - 1);

      if (error) {
        throw error;
      }

      // Update hasMoreUsers flag based on if we received fewer results than requested
      hasMoreUsers.value = data.length === batchSize;
      userIds.push(...data.map(user => user[User.fields.id]));
    }

    return userIds;
  };

  // Load matches based on current filters
  const loadMatches = async () => {
    reset();

    try {
      await loadMoreMatches({ done: () => {} });
    } catch (error) {
      console.error('Error loading matches:', error);
      snackbarStore.set('error', 'Error loading matches');
    } finally {
      loading.value = false;
    }
  };

  // Filter matches based on user preference
  const filterMatches = (matchData) => {
    const { have, want } = matchData;

    // Apply filter based on matchFilter value
    switch (matchFilter.value) {
      case 'bothSides':
        return have.length > 0 && want.length > 0;
      case 'oneSide':
        return have.length > 0 || want.length > 0;
      case 'all':
      default:
        return true;
    }
  };

  // Load more matches for infinite scrolling
  const loadMoreMatches = async ({ done }) => {
    if (!hasMoreUsers.value) {
      done('empty');
      return;
    }

    try {
      loading.value = true;
      const users = await getUsers();

      // Filter out users we've already processed
      const newUsers = users.filter(userId => !processedUsers.value.has(userId));

      if (!newUsers.length) {
        userPage.value++;
        done(hasMoreUsers.value ? 'ok' : 'empty');
        return;
      }

      // Mark these users as processed
      newUsers.forEach(userId => processedUsers.value.add(userId));

      // Get all collection data
      const collectionsData = await getCollectionApps([authUser.id, ...newUsers]);

      // My have and want
      const myHave = collectionsData[authUser.id].tradelist;
      const myWant = collectionsData[authUser.id].wishlist;

      // Track if this batch found any valid matches
      let validMatchesFound = false;

      // Process each user for matches
      for (const userId of newUsers) {
        if (!collectionsData[userId]) { continue; }

        const theirHave = collectionsData[userId].tradelist;
        const theirWant = collectionsData[userId].wishlist;

        // Find matching apps (what I have that they want)
        const have = myHave.filter(appId => theirWant.includes(appId));

        // Find matching apps (what I want that they have)
        const want = myWant.filter(appId => theirHave.includes(appId));

        // Only add match if it passes the filter
        if (filterMatches({ have, want })) {
          matches.value.push({
            user: userId,
            have,
            want
          });
          validMatchesFound = true;
        }
      }

      // Auto-load next batch if no matches found and more users are available
      if (!validMatchesFound && hasMoreUsers.value) {
        userPage.value++;
        // Instead of recursive call, we'll just let the function return
        // and the infinite scroll component will trigger another load if needed
        done('ok');
        return;
      }

      // Increment the page for next load
      userPage.value++;

      if (userPage.value === 2 && matches.value.length === 0) {
        snackbarStore.set('warning', 'No matches found with current filters');
      }

      done(hasMoreUsers.value ? 'ok' : 'empty');
    } catch (error) {
      console.error('Error loading more matches:', error);
      snackbarStore.set('error', 'Error loading more matches');
      done('error');
    } finally {
      loading.value = false;
    }
  };

  // Call loadMatches when the action is triggered
  const handleLoadMatches = () => loadMatches();

  // Apply filters on page load if parameters exist
  onMounted(() => {
    if (selectedUser.value || selectedApp.value) {
      loadMatches();
    }
  });

  const title = 'Matches';
  const breadcrumbs = [
    { title: 'Home', to: '/' },
    { title, disabled: true }
  ];

  useHead({ title });

  definePageMeta({
    middleware: 'authenticated'
  });
</script>

<template>
  <s-page-content :breadcrumbs="breadcrumbs">
    <v-card class="h-100 pa-4">
      <!-- Filters section -->
      <v-card class="mb-4 border rounded-lg">
        <v-card-title class="text-tonal">
          <v-icon
            class="mr-2"
            icon="mdi-filter-outline"
          />
          Match Filters
        </v-card-title>
        <v-divider />
        <v-card-text>
          <v-row>
            <!-- User selection -->
            <v-col
              cols="12"
              sm="6"
              xl="3"
            >
              <v-card
                class="h-100"
                variant="flat"
              >
                <v-card-subtitle>User Filter</v-card-subtitle>
                <v-card-text>
                  <v-btn-toggle
                    v-model="singleUser"
                    class="mb-2 border"
                    color="tonal"
                  >
                    <v-btn :value="false">
                      <v-icon
                        icon="mdi-account-group"
                        start
                      />
                      All Users
                    </v-btn>
                    <v-btn :value="true">
                      <v-icon
                        icon="mdi-account"
                        start
                      />
                      Single User
                    </v-btn>
                  </v-btn-toggle>

                  <div
                    v-if="singleUser"
                    class="mt-2"
                  >
                    <dialog-select-user @select:user="user => selectedUser = user">
                      <template #activator="{ props }">
                        <v-btn
                          v-bind="props"
                          block
                          variant="tonal"
                        >
                          <v-icon
                            icon="mdi-account-search"
                            start
                          />
                          {{ selectedUser ? 'Change User' : 'Select User' }}
                        </v-btn>
                      </template>
                    </dialog-select-user>
                  </div>
                </v-card-text>
              </v-card>
            </v-col>

            <!-- App selection -->
            <v-col
              cols="12"
              sm="6"
              xl="3"
            >
              <v-card
                class="h-100"
                variant="flat"
              >
                <v-card-subtitle>App Filter</v-card-subtitle>
                <v-card-text>
                  <v-btn-toggle
                    v-model="singleApp"
                    class="mb-2 border"
                    color="tonal"
                  >
                    <v-btn :value="false">
                      <v-icon
                        icon="mdi-apps"
                        start
                      />
                      All Apps
                    </v-btn>
                    <v-btn :value="true">
                      <v-icon
                        icon="mdi-gamepad-variant"
                        start
                      />
                      Single App
                    </v-btn>
                  </v-btn-toggle>

                  <div
                    v-if="singleApp"
                    class="mt-2"
                  >
                    <dialog-select-app @select:app="app => selectedApp = app">
                      <template #activator="{ props }">
                        <v-btn
                          v-bind="props"
                          block
                          variant="tonal"
                        >
                          <v-icon
                            icon="mdi-gamepad-square"
                            start
                          />
                          {{ selectedApp ? 'Change App' : 'Select App' }}
                        </v-btn>
                      </template>
                    </dialog-select-app>
                  </div>
                </v-card-text>
              </v-card>
            </v-col>

            <!-- Match type filter -->
            <v-col
              cols="12"
              xl="6"
            >
              <v-card
                class="h-100"
                variant="flat"
              >
                <v-card-subtitle>Match Type</v-card-subtitle>
                <v-card-text>
                  <v-btn-toggle
                    v-model="matchFilter"
                    class="mb-2 border"
                    color="tonal"
                    divided
                  >
                    <v-btn
                      v-for="option in matchFilterOptions"
                      :key="option.value"
                      :value="option.value"
                    >
                      <v-icon
                        icon="mdi-filter-outline"
                        start
                      />
                      {{ option.title }}
                    </v-btn>
                  </v-btn-toggle>
                </v-card-text>
              </v-card>
            </v-col>
          </v-row>

          <div class="d-flex justify-center mt-2">
            <v-btn
              block
              color="tonal"
              :disabled="loading || (singleUser && !selectedUser) || (singleApp && !selectedApp)"
              prepend-icon="mdi-magnify"
              size="large"
              variant="tonal"
              @click="handleLoadMatches"
            >
              {{ loading ? 'Loading...' : 'Find Matches' }}
            </v-btn>
          </div>
        </v-card-text>
      </v-card>

      <div
        v-if="matches.length === 0 && !loading"
        class="d-flex justify-center align-center h-100"
      >
        <div class="text-disabled font-italic text-center">
          <p>No matches found.</p>
          <p>Try adjusting your filters or updating your wishlist and tradelist.</p>
          <br>
          <p v-if="selectedApp">
            Consider buying it after checking the deals on
            <a
              :href="`https://gg.deals/steam/app/${selectedApp}`"
              rel="noopener"
              target="_blank"
            >GG.Deals</a>.
          </p>
        </div>
      </div>

      <div
        v-if="loading && matches.length === 0"
        class="d-flex justify-center align-center h-100"
      >
        <v-progress-circular
          indeterminate
          size="64"
        />
      </div>

      <v-infinite-scroll
        empty-text=""
        margin="100"
        mode="intersect"
        @load="loadMoreMatches"
      >
        <div
          v-for="match in matches"
          :key="`match-${match.user}`"
        >
          <v-card class="border rounded-lg mb-4">
            <v-card-title class="d-flex align-center ga-2">
              Match with

              <rich-profile-link :user-id="match.user" />

              <v-spacer />

              <v-btn
                v-tooltip:top="`Click to trade with this user`"
                target="_blank"
                :to="`/trade/new?partner=${match.user}`"
                variant="tonal"
              >
                <v-icon
                  icon="mdi-plus"
                  start
                />
                Trade
              </v-btn>
            </v-card-title>
            <v-divider />
            <v-row class="pa-2">
              <v-col
                cols="12"
                lg="6"
              >
                <h3 class="mb-2 d-flex align-center ga-1">
                  <v-icon icon="mdi-swap-horizontal-circle-outline" />
                  <span class="text-disabled">You have</span>
                  <strong>{{ match.have.length }}</strong>
                  <span class="text-disabled">
                    {{ match.have.length === 1 ? 'item' : 'items' }} they want
                  </span>
                </h3>
                <table-apps
                  v-if="match.have.length"
                  :only-apps="match.have"
                  simple
                  style="min-height: 0;"
                />
                <v-alert
                  v-else
                  density="compact"
                  icon="mdi-information"
                  text="Nothing to offer"
                  type="info"
                  variant="tonal"
                />
              </v-col>
              <v-col
                cols="12"
                lg="6"
              >
                <h3 class="mb-2 d-flex align-center ga-1">
                  <v-icon icon="mdi-heart-circle-outline" />
                  <span class="text-disabled">They have</span>
                  <strong>{{ match.want.length }}</strong>
                  <span class="text-disabled">
                    {{ match.want.length === 1 ? 'item' : 'items' }} you want
                  </span>
                </h3>
                <table-apps
                  v-if="match.want.length"
                  :only-apps="match.want"
                  simple
                  style="min-height: 0;"
                />
                <v-alert
                  v-else
                  density="compact"
                  icon="mdi-information"
                  text="Nothing you want"
                  type="info"
                  variant="tonal"
                />
              </v-col>
            </v-row>
          </v-card>
        </div>

        <!-- Loading indicator for infinite scroll -->
        <template #loading>
          <div class="d-flex justify-center py-4">
            <v-progress-circular
              v-if="hasMoreUsers"
              indeterminate
            />
          </div>
        </template>
      </v-infinite-scroll>
    </v-card>
  </s-page-content>
</template>