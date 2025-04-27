<script setup>
  import { formatNumber } from '~/assets/js/format';
  import { toAccountID } from '~/assets/js/steamid';

  const props = defineProps({
    user: {
      type: Object,
      required: true
    },
    stats: {
      type: Object,
      default: null
    }
  });

  const { User, Review, Trade } = useORM();

  const { data: stats, error: statsError } = await useLazyAsyncData(`user-stats-${props.user.id}`, () => {
    if (!props.stats) {
      return props.stats;
    }

    const user = new User(props.user);
    return user.getStatistics();
  }, {
    getCachedData: (key, nuxtApp) => {
      return nuxtApp.payload.data[key] || nuxtApp.static.data[key];
    }
  });

  const lastReview = ref(null);
  watch(() => stats.value?.lastReview, async (id) => {
    if (!id) {
      return;
    }

    const review = new Review(id);
    await review.load();
    lastReview.value = review.toObject();
  }, {
    immediate: true
  });

  const lastTrade = ref(null);
  watch(() => stats.value?.lastTrade, async (id) => {
    if (!id) {
      return;
    }

    const trade = new Trade(id);
    await trade.load();
    lastTrade.value = trade.toObject();
  }, {
    immediate: true
  });

  const { data: partners, error: partnersError } = await useLazyAsyncData(`user-partners-${props.user.id}`, async () => {
    const user = new User(props.user);
    return user.getTradePartners();
  }, {
    getCachedData: (key, nuxtApp) => {
      return nuxtApp.payload.data[key] || nuxtApp.static.data[key];
    }
  });

  const snackbarStore = useSnackbarStore();
  const copy = value => {
    navigator.clipboard.writeText(value);
    snackbarStore.set('success', 'Copied to clipboard');
  };
</script>

<template>
  <div
    v-if="stats"
    class="w-100 h-0"
    style="min-height: 300px;"
  >
    <v-row dense>
      <v-col
        class="rounded pa-4"
        cols="12"
        md="6"
      >
        <h2>
          <v-icon
            class="mt-n1 mr-1"
            icon="mdi-card-text"
            size="small"
          />
          Details
        </h2>
        <v-table class="mb-4">
          <tbody>
            <tr>
              <td class="text-overline">
                User ID
              </td>
              <td>
                {{ user.id }}
                <v-icon
                  class="ml-1"
                  color="disabled"
                  icon="mdi-content-copy"
                  size="x-small"
                  @click="copy(user.id)"
                />
              </td>
            </tr>
            <tr>
              <td class="text-overline">
                Steam ID64
              </td>
              <td>
                {{ user.steamId }}
                <v-icon
                  class="ml-1"
                  color="disabled"
                  icon="mdi-content-copy"
                  size="x-small"
                  @click="copy(user.steamId)"
                />
              </td>
            </tr>
            <tr>
              <td class="text-overline">
                Steam ID3
              </td>
              <td>
                [U:1:{{ toAccountID(user.steamId) }}]
                <v-icon
                  class="ml-1"
                  color="disabled"
                  icon="mdi-content-copy"
                  size="x-small"
                  @click="copy(`[U:1:${toAccountID(user.steamId)}]`)"
                />
              </td>
            </tr>
            <tr>
              <td class="text-overline">
                Joined
              </td>
              <td>
                <rich-date
                  class="text-disabled"
                  :date="user.createdAt"
                />
              </td>
            </tr>
          </tbody>
        </v-table>

        <h2>
          <v-icon
            class="mt-n1 mr-1"
            icon="mdi-apps"
            size="small"
          />
          Collections
        </h2>
        <v-table class="mb-4">
          <tbody>
            <tr>
              <td class="text-overline">
                Total
              </td>
              <td>
                {{ formatNumber(stats.totalCollections) }}
                <span class="text-disabled">
                  {{ stats.totalCollections === 1 ? 'collection' : 'collections' }}
                </span>
              </td>
            </tr>
            <tr>
              <td class="text-overline">
                Library
              </td>
              <td>
                {{ formatNumber(stats.totalLibrary) }}
                <span class="text-disabled">apps</span>
              </td>
            </tr>
            <tr>
              <td class="text-overline">
                Wishlist
              </td>
              <td>
                {{ formatNumber(stats.totalWishlist) }}
                <span class="text-disabled">apps</span>
              </td>
            </tr>
            <tr>
              <td class="text-overline">
                Tradelist
              </td>
              <td>
                {{ formatNumber(stats.totalTradelist) }}
                <span class="text-disabled">apps</span>
              </td>
            </tr>
            <tr>
              <td class="text-overline">
                Blacklist
              </td>
              <td>
                {{ formatNumber(stats.totalBlacklist) }}
                <span class="text-disabled">apps</span>
              </td>
            </tr>
          </tbody>
        </v-table>
      </v-col>

      <v-divider
        v-if="$vuetify.display.mdAndUp"
        vertical
      />

      <v-col
        class="pa-4 d-flex flex-column justify-space-between"
        cols="12"
        md="6"
      >
        <h2>
          <v-icon
            class="mt-n1 mr-1"
            icon="mdi-star"
            size="small"
          />
          Reviews
        </h2>
        <v-table class="mb-4">
          <tbody>
            <tr v-if="lastReview">
              <td class="text-overline">
                Latest
              </td>
              <td>
                <span class="text-disabled">
                  From
                </span>
                <rich-profile-link
                  hide-avatar
                  :user-id="lastReview.userId"
                />
                <rich-date
                  class="text-disabled"
                  :date="lastReview.createdAt"
                />
              </td>
            </tr>
            <tr>
              <td class="text-overline">
                Received
              </td>
              <td>
                {{ formatNumber(stats.totalReviewsReceived) }}
                <span class="text-disabled">
                  {{ stats.totalReviewsReceived === 1 ? 'review' : 'reviews' }}
                </span>
              </td>
            </tr>
            <tr>
              <td class="text-overline">
                Given
              </td>
              <td>
                {{ formatNumber(stats.totalReviewsGiven) }}
                <span class="text-disabled">
                  {{ stats.totalReviewsGiven === 1 ? 'review' : 'reviews' }}
                </span>
              </td>
            </tr>
          </tbody>
        </v-table>

        <h2>
          <v-icon
            class="mt-n1 mr-1"
            icon="mdi-swap-horizontal"
            size="small"
          />
          Trades
        </h2>
        <v-table class="mb-4">
          <tbody>
            <tr v-if="lastTrade">
              <td class="text-overline">
                Latest
              </td>
              <td>
                <span class="text-disabled">
                  With
                </span>
                <rich-profile-link
                  hide-avatar
                  :user-id="lastTrade.senderId === props.user.id ? lastTrade.receiverId : lastTrade.senderId"
                />
                <rich-date
                  class="text-disabled"
                  :date="lastTrade.createdAt"
                />
              </td>
            </tr>
            <tr>
              <td class="text-overline">
                Completed
              </td>
              <td>
                {{ formatNumber(stats.totalCompletedTrades) }}
                <span class="text-disabled">
                  {{ stats.totalCompletedTrades === 1 ? 'trade' : 'trades' }}, with
                </span>
                {{ formatNumber(stats.totalUniqueTrades) }}
                <span class="text-disabled">
                  {{ stats.totalUniqueTrades === 1 ? 'user' : 'users' }}
                </span>
              </td>
            </tr>
            <tr>
              <td class="text-overline">
                Pending
              </td>
              <td>
                {{ formatNumber(stats.totalPendingTrades) }}
                <span class="text-disabled">
                  {{ stats.totalPendingTrades === 1 ? 'trade' : 'trades' }}
                </span>
              </td>
            </tr>
            <tr>
              <td class="text-overline">
                Accepted
              </td>
              <td>
                {{ formatNumber(stats.totalAcceptedTrades) }}
                <span class="text-disabled">
                  {{ stats.totalAcceptedTrades === 1 ? 'trade' : 'trades' }}
                </span>
              </td>
            </tr>
            <tr>
              <td class="text-overline">
                Declined
              </td>
              <td>
                {{ formatNumber(stats.totalDeclinedTrades) }}
                <span class="text-disabled">
                  {{ stats.totalDeclinedTrades === 1 ? 'trade' : 'trades' }}
                </span>
              </td>
            </tr>
            <tr>
              <td class="text-overline">
                Aborted
              </td>
              <td>
                {{ formatNumber(stats.totalAbortedTrades) }}
                <span class="text-disabled">
                  {{ stats.totalAbortedTrades === 1 ? 'trade' : 'trades' }}
                </span>
              </td>
            </tr>
            <tr>
              <td class="text-overline">
                Disputed
              </td>
              <td>
                {{ formatNumber(stats.totalDisputedTrades) }}
                <span class="text-disabled">
                  {{ stats.totalDisputedTrades === 1 ? 'trade' : 'trades' }}
                </span>
              </td>
            </tr>
          </tbody>
        </v-table>

        <div v-if="partners?.length">
          <b>Top {{ partners.length }} trading partners:</b>

          <v-row
            v-for="(partner, index) in partners"
            :key="`trade-${partner.partnerId}`"
            class="d-flex flex-row align-center justify-space-between"
            no-gutters
          >
            <span>
              {{ index + 1 }}.
              <rich-profile-link :user-id="partner.partnerId" />
            </span>
            <span>{{ formatNumber(partner.totalCompletedTrades) }}
              <span class="text-disabled">trades</span>
            </span>
          </v-row>
        </div>
      </v-col>
    </v-row>
  </div>
  <div
    v-else-if="statsError || partnersError"
    class="error-message"
  >
    Error loading user statistics
  </div>
  <div
    v-else
    class="loading"
  >
    <v-progress-circular indeterminate />
  </div>
</template>

<style lang="scss" scoped>
  .v-table :deep(.text-overline) {
    width: 150px;
    white-space: nowrap;
  }
</style>