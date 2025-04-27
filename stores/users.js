/**
 * Store for users.
 *
 * @type {StoreDefinition<"users", {
 *   online: Object
 * }>}
 */
export const useUsersStore = defineStore('users', {
  state: () => ({
    online: {}
  }),

  actions: {
    setOnline(presenceState) {
      const items = Object.values(presenceState).flat();
      this.online = items.reduce((acc, item) => {
        const { user_id, online_at } = item;
        acc[user_id] = online_at;
        return acc;
      }, {}); ;
    }
  }
});
