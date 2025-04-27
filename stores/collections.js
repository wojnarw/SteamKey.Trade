/**
 * Store your personal app collections.
 *
 * @type {StoreDefinition<"collections", {
 *   library: Array,
 *   wishlist: Array,
 *   tradelist: Array,
 *   blacklist: Array,
 * }>}
 */
export const useCollectionsStore = defineStore('collections', {
  persist: true,

  state: () => ({
    library: [],
    wishlist: [],
    tradelist: [],
    blacklist: []
  }),

  getters: {
    inCollection: state => (type, appid) => {
      if (typeof type !== 'string' || isNaN(appid) || !state[type]) {
        return false;
      }

      return state[type].includes(Number(appid));
    },

    inLibrary: state => appid => {
      return state.inCollection('library', appid);
    },

    inWishlist: state => appid => {
      return state.inCollection('wishlist', appid);
    },

    inTradelist: state => appid => {
      return state.inCollection('tradelist', appid);
    },

    inBlacklist: state => appid => {
      return state.inCollection('blacklist', appid);
    }
  },

  actions: {
    setCollection(type, appids) {
      if (typeof type !== 'string' || !Array.isArray(appids)) {
        return;
      }

      this[type] = [...new Set(markRaw(appids).map(Number).filter(Boolean))];
    },

    setLibrary(appids) {
      return this.setCollection('library', appids);
    },

    setWishlist(appids) {
      return this.setCollection('wishlist', appids);
    },

    setTradelist(appids) {
      return this.setCollection('tradelist', appids);
    },

    setBlacklist(appids) {
      return this.setCollection('blacklist', appids);
    }
  }
});
