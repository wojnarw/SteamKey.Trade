<script setup>
  const route = useRoute();
  const router = useRouter();

  const singleUser = ref(false);
  const singleApp = ref(false);
  const selectedUser = ref(null);
  const selectedApp = ref(null);

  const snackbarStore = useSnackbarStore();
  const { user: authUser } = useAuthStore();
  const supabase = useSupabaseClient();
  const { User, Collection } = useORM();

  const loading = ref(false);
  const matches = ref([]);

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

  // Get users to match against
  const getUsers = async () => {
    const userIds = [];

    if (singleUser.value) {
      if (!selectedUser.value) {
        return userIds;
      }
      userIds.push(selectedUser.value);
    } else {
      // Fetch active users (limited to 100 for performance)
      const { data, error } = await supabase
        .from(User.table)
        .select(User.fields.id)
        .neq(User.fields.id, authUser.id)
        .limit(100);

      if (error) {
        throw error;
      }

      userIds.push(...data.map(user => user[User.fields.id]));
    }

    return userIds;
  };

  // Filter matches by specific app if selected
  const filterMatchesByApp = (collectionsData) => {
    if (!singleApp.value || !selectedApp.value) {
      return collectionsData;
    }

    const appId = selectedApp.value;
    const filteredData = {};

    for (const [userId, collections] of Object.entries(collectionsData)) {
      filteredData[userId] = {
        tradelist: collections.tradelist.filter(id => id === appId),
        wishlist: collections.wishlist.filter(id => id === appId)
      };
    }

    return filteredData;
  };

  // Load matches based on current filters
  const loadMatches = async () => {
    loading.value = true;
    matches.value = [];

    try {
      const users = await getUsers();
      if (!users.length) {
        snackbarStore.set('error', 'No users to match');
        loading.value = false;
        return;
      }

      // Get all collection data
      let collectionsData = await getCollectionApps([authUser.id, ...users]);

      // Apply app filter if needed
      if (singleApp.value && selectedApp.value) {
        collectionsData = filterMatchesByApp(collectionsData);
      }

      // My have and want
      const myHave = collectionsData[authUser.id].tradelist;
      const myWant = collectionsData[authUser.id].wishlist;

      // Process each user for matches
      for (const userId of users) {
        if (!collectionsData[userId]) { continue; }

        const theirHave = collectionsData[userId].tradelist;
        const theirWant = collectionsData[userId].wishlist;

        // Find matching apps (what I have that they want)
        const have = myHave.filter(appId => theirWant.includes(appId));

        // Find matching apps (what I want that they have)
        const want = myWant.filter(appId => theirHave.includes(appId));

        // Only add users with at least one match
        if (have.length > 0 || want.length > 0) {
          matches.value.push({
            user: userId,
            have,
            want
          });
        }
      }

      if (matches.value.length === 0) {
        snackbarStore.set('warning', 'No matches found with current filters');
      }
    } catch (error) {
      console.error('Error loading matches:', error);
      snackbarStore.set('error', 'Error loading matches');
    } finally {
      loading.value = false;
    }
  };

  // Update URL with current filter parameters
  const updateUrlParameters = () => {
    const query = { ...route.query };

    // Update app parameter
    if (singleApp.value && selectedApp.value) {
      query.app = selectedApp.value.toString();
    } else {
      delete query.app;
    }

    // Update user parameter
    if (singleUser.value && selectedUser.value) {
      query.user = selectedUser.value.toString();
    } else {
      delete query.user;
    }

    // Update URL without reloading the page
    router.replace({ query }, { shallow: true });
  };

  // Apply URL parameters on page load
  const applyUrlParameters = async () => {
    // Check for user parameter
    if (route.query.user) {
      singleUser.value = true;
      selectedUser.value = route.query.user;
    }

    // Check for app parameter
    if (route.query.app) {
      singleApp.value = true;
      selectedApp.value = route.query.app;
    }

    // If we have either parameter, automatically load matches
    if (route.query.user || route.query.app) {
      await loadMatches();
    }
  };

  // Watch for changes in filters to update URL
  watch([singleUser, selectedUser, singleApp, selectedApp], updateUrlParameters);

  // Call loadMatches when the action is triggered
  const handleLoadMatches = async () => {
    await loadMatches();
    updateUrlParameters();
  };

  // Initialize based on URL parameters
  onMounted(applyUrlParameters);

  const title = 'Matches';
  const breadcrumbs = [
    { title: 'Home', to: '/' },
    { title, disabled: true }
  ];

  useHead({ title });
</script>

<template>
  <s-page-content :breadcrumbs="breadcrumbs">
    <v-card class="h-100 pa-4">
      <div class="d-flex flex-column flex-md-row align-md-center justify-space-between ga-4 mb-4">
        <!-- User selection -->
        <div class="d-flex align-center ga-4">
          <v-radio-group
            v-model="singleUser"
            hide-details
            inline
          >
            <v-radio
              label="All users"
              :value="false"
            />
            <v-radio
              label="Single user"
              :value="true"
            />
          </v-radio-group>

          <dialog-select-user
            v-if="singleUser"
            @select:user="user => selectedUser = user"
          >
            <template #activator="{ props }">
              <v-btn
                v-bind="props"
                variant="tonal"
              >
                {{ selectedUser ? 'Change user' : 'Select user' }}
              </v-btn>
            </template>
          </dialog-select-user>
        </div>

        <!-- App selection -->
        <div class="d-flex align-center ga-2">
          <v-radio-group
            v-model="singleApp"
            hide-details
            inline
          >
            <v-radio
              label="All Apps"
              :value="false"
            />
            <v-radio
              label="Single App"
              :value="true"
            />
          </v-radio-group>

          <dialog-select-app
            v-if="singleApp"
            @select:app="app => selectedApp = app"
          >
            <template #activator="{ props }">
              <v-btn
                v-bind="props"
                variant="tonal"
              >
                {{ selectedApp ? 'Change App' : 'Select App' }}
              </v-btn>
            </template>
          </dialog-select-app>
        </div>

        <v-btn
          :disabled="(singleUser && !selectedUser) || (singleApp && !selectedApp)"
          :loading="loading"
          variant="tonal"
          @click="handleLoadMatches"
        >
          Find Matches
        </v-btn>
      </div>

      <div
        v-if="matches.length === 0 && !loading"
        class="d-flex justify-center align-center h-100"
      >
        <div class=" text-disabled font-italic text-center">
          <p>No matches found.</p>
          <p>Try adjusting your filters or updating your wishlist and tradelist.</p>
        </div>
      </div>

      <div
        v-if="loading"
        class="d-flex justify-center align-center h-100"
      >
        <v-progress-circular
          color="primary"
          indeterminate
          size="64"
        />
      </div>

      <nuxt-link
        v-for="match in matches"
        :key="`match-${match.user}`"
        v-tooltip:top="`Click to trade with this user`"
        class="text-decoration-none text-primary mb-4"
        target="_blank"
        :to="`/trade/new?partner=${match.user}`"
      >
        <v-card
          v-ripple
          class="cursor-pointer mb-4"
          variant="outlined"
        >
          <v-card-title class="d-flex align-center ga-2">
            Match with
            <rich-profile-link
              no-link
              :user-id="match.user"
            />
          </v-card-title>
          <v-divider />
          <v-row class="pa-2">
            <v-col
              cols="12"
              md="6"
            >
              <h3 class="mb-2 d-flex align-center">
                <v-icon
                  class="mr-2"
                  icon="mdi-swap-horizontal-circle-outline"
                />
                You have {{ match.have.length }} {{ match.have.length === 1 ? 'item' : 'items' }} they want
              </h3>
              <table-apps
                v-if="match.have.length"
                :only-apps="match.have"
                simple
              />
              <v-alert
                v-else
                density="compact"
                text="Nothing to offer"
                type="info"
                variant="tonal"
              />
            </v-col>
            <v-col
              cols="12"
              md="6"
            >
              <h3 class="mb-2 d-flex align-center">
                <v-icon
                  class="mr-2"
                  icon="mdi-heart-circle-outline"
                />
                They have {{ match.want.length }} {{ match.want.length === 1 ? 'item' : 'items' }} you want
              </h3>
              <table-apps
                v-if="match.want.length"
                :only-apps="match.want"
                simple
              />
              <v-alert
                v-else
                density="compact"
                text="Nothing you want"
                type="info"
                variant="tonal"
              />
            </v-col>
          </v-row>
        </v-card>
      </nuxt-link>
    </v-card>
  </s-page-content>
</template>