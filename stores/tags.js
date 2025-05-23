/**
 * Store for tags
 *
 * @type {StoreDefinition<"tags", {
 *   names: null | Object,
 *   types: null | Object,
 *   refreshedAt: null | Date
 * }>}
 */
export const useTagsStore = defineStore('tags', {
  persist: true,

  state: () => ({
    names: null,
    types: null,
    refreshedAt: null
  }),

  actions: {
    setNames(names) {
      this.names = markRaw(names);
    },

    setTypes(types) {
      this.types = markRaw(types);
    },

    setFromRecords(records) {
      const names = {};
      const types = {};

      records.forEach((record) => {
        names[record.id] = record.title;
        types[record.id] = record.type;
      });

      this.setNames(names);
      this.setTypes(types);
    },

    /**
     * Get all names (of a specific type)
     *
     * @param {string} typeFilter - The type of tags to get (optional)
     * @returns {Object} - An object mapping tag IDs to names
     */
    getNames(typeFilter) {
      return Object.fromEntries(
        Object.entries(this.names).filter(([id]) =>
          !typeFilter || this.types[id] === typeFilter
        )
      );
    },

    /**
     * Refresh tags if they are not yet set or older than 24 hours.
     *
     * @returns {Promise<void>}
     */
    async refreshTags() {
      // Refresh tags if they are not set or if they are older than 24 hours
      if (Object.keys(this.names || {}).length && Object.keys(this.types || {}).length && this.refreshedAt && Date.now() - this.refreshedAt < 24 * 60 * 60 * 1000) {
        return;
      }

      const supabase = useSupabaseClient();
      try {
        const { data } = await supabase
          .from('tags')
          .select('id, title, type');

        if (data) {
          this.setFromRecords(data);
          this.refreshedAt = Date.now();
        }
      } catch (error) {
        console.error(error);
      }
    },

    reset() {
      this.names = null;
      this.types = null;
    }
  }
});
