/**
 * Store for apps
 *
 * @type {StoreDefinition<"apps", {
 *   fuse: null | Object,
 *   destroy: null | Function,
 *   defaultOptions: Object,
 *   names: null | Array,
 *   headers: null | Object,
 *   metadataRefreshedAt: null | Date,
 *   facets: null | Array,
 *   facetsRefreshedAt: null | Date
 * }>}
 */
export const useAppsStore = defineStore('apps', {
  persist: true,

  state: () => ({
    fuse: null,
    destroy: null,
    defaultOptions: markRaw({
      includeScore: true,
      threshold: 0.175,
      keys: ['names']
    }),
    names: null,
    headers: null,
    metadataRefreshedAt: null,
    facets: null,
    facetsRefreshedAt: null
  }),

  getters: {
    isReady(state) {
      return !!state.names;
    }
  },

  actions: {
    setNames(names) {
      this.names = markRaw(names);
      this.setSearchOptions(this.defaultOptions);
    },

    setHeaders(headers) {
      this.headers = markRaw(headers);
    },

    setSearchOptions(options) {
      if (this.fuse) {
        this.destroy();
      }
      const { search, destroy } = useFuse(this.names, options);
      this.fuse = search;
      this.destroy = destroy;
    },

    // TODO: Use supabase search instead?
    search(query) {
      return this.fuse(query);
    },

    /**
     * Refresh app metadata if they are not yet set or if they are older than 24 hours
     *
     * @returns {Promise<void>}
     */
    async refreshMetadata() {
      // Refresh metadata if they are not set or if they are older than 24 hours
      if (this.names && this.headers && this.metadataRefreshedAt && Date.now() - this.metadataRefreshedAt < 24 * 60 * 60 * 1000) {
        return;
      }

      const supabase = useSupabaseClient();
      try {
        const { data } = supabase.storage.from('assets').getPublicUrl('apps.metadata.json.gz');
        const response = await fetch(data.publicUrl)
          .then(res => {
            const decompressor = new DecompressionStream('gzip');
            const decompressionStream = res.body.pipeThrough(decompressor);
            return new Response(decompressionStream).arrayBuffer();
          })
          .then(buffer => {
            return new TextDecoder('utf-8').decode(buffer);
          });

        const apps = JSON.parse(response);
        this.setNames(apps.map(({ id, title, altTitles }) => ({
          appid: id,
          names: [title].concat(altTitles || [])
        })));

        this.setHeaders(Object.fromEntries(apps.map(({ id, header }) => [id, header])));

        this.metadataRefreshedAt = Date.now();
      } catch (error) {
        console.error(error);
      }
    },

    /**
     * Refresh app facets if they are not yet set or if they are older than 24 hours
     *
     * @returns {Promise<void>}
     */
    async refreshFacets() {
      // Refresh facets if they are not set or if they are older than 24 hours
      if (this.facets && this.facetsRefreshedAt && Date.now() - this.facetsRefreshedAt < 24 * 60 * 60 * 1000) {
        return;
      }

      const supabase = useSupabaseClient();
      const { App } = useORM();

      try {
        const facets = await App.getFacets(supabase);
        this.facets = facets;
        this.facetsRefreshedAt = Date.now();
      } catch (error) {
        console.error(error);
      }
    },

    reset() {
      this.setSearchOptions(this.defaultOptions);
    }
  }
});
