/**
 * Store for user matches (have/want combos)
 *
 * Structure:
 * matches: {
 *   users: {
 *     [userId]: { have: Array, want: Array, refreshedAt: number }
 *   }
 * }
 */

export const useMatchesStore = defineStore('matches', {
  persist: true,

  state: () => ({
    users: {} // { [userId]: { have, want, refreshedAt } }
  }),

  actions: {
    /**
     * Set matches for a user
     * @param {string|number} userId
     * @param {Array} have
     * @param {Array} want
     */
    setUserMatches(userId, have, want) {
      this.users[userId] = markRaw({
        have,
        want,
        refreshedAt: Date.now()
      });
    },

    /**
     * Get matches for a user if cache is fresh (<24h)
     * @param {string|number} userId
     * @returns {null|{have:Array, want:Array}}
     */
    getUserMatches(userId) {
      const entry = this.users[userId];
      if (!entry) { return null; }
      if (Date.now() - entry.refreshedAt > 24 * 60 * 60 * 1000) { return null; }
      return entry;
    },

    /**
     * Set multiple users' matches at once
     * @param {Object} userMatches - { [userId]: { have, want } }
     */
    setFromRecords(userMatches) {
      Object.entries(userMatches).forEach(([userId, value]) => {
        this.setUserMatches(userId, value.have, value.want);
      });
    },

    /**
     * Reset all cached matches
     */
    reset() {
      this.users = {};
    }
  }
});
