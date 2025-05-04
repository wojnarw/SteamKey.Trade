let expirer = null;

/**
 * Store your authentication state data.
 *
 * @type {StoreDefinition<"auth", {
 *   user: null | Object
 *   preferences: null | Object
 *   fromPath: null | string,
 *   password: null | string,
 *   passwordExpiry: null | Number
 * }>}
 */
export const useAuthStore = defineStore('auth', {
  persist: true,

  state: () => ({
    user: null,
    preferences: null,
    fromPath: null,
    password: null,
    passwordExpiry: null
  }),

  getters: {
    isLoggedIn: ({ user }) => !!user,

    me: ({ user }) => {
      if (!user) {
        return null;
      }
      const { User } = useORM();
      return new User(user);
    }
  },

  actions: {
    setPassword(password, expiresIn) {
      this.password = password;
      if (expirer) {
        clearTimeout(expirer);
      }
      if (expiresIn) {
        this.passwordExpiry = Date.now() + expiresIn;
        expirer = setTimeout(() => {
          this.password = null;
        }, expiresIn);
      }
    },

    setUser(user) {
      this.user = user;
    },

    setPreferences(preferences) {
      this.preferences = preferences;
    },

    setFromPath(fromPath) {
      if (fromPath?.startsWith('/login') || fromPath?.startsWith('/logout')) {
        return;
      }

      this.fromPath = typeof fromPath === 'string' && fromPath || null;
    },

    setPhotoUrl(url) {
      if (this.user) {
        this.user.avatar = url;
      }
    },

    setPublicKey(publicKey) {
      if (this.user) {
        this.user.publicKey = publicKey;
      }
    },

    updateUserCollections() {
      const supabase = useSupabaseClient();
      const { Collection } = useORM();
      const collectionsStore = useCollectionsStore();

      Collection.getMasterCollectionsApps(supabase, this.user.id)
        .then(masterCollections => {
          for (const type in masterCollections) {
            const appIds = masterCollections[type] || [];
            collectionsStore.setCollection(type, appIds);
          }
        })
        .catch(error => {
          console.error('Error fetching master collections:', error);
        });
    },

    onAuthStateChange(authEvent, session) {
      const supabase = useSupabaseClient();
      const { User } = useORM();
      const collectionsStore = useCollectionsStore();

      const oldUser = this.user;
      const newUser = session?.user ?? null;
      const gotLoggedIn = !oldUser && !!newUser;
      const gotLoggedOut = !!oldUser && !newUser;

      // console.log({ authEvent, session, gotLoggedIn, gotLoggedOut });
      if (gotLoggedOut) {
        supabase.removeAllChannels();
        this.setUser(null);
        this.setPreferences(null);
        this.setPassword(null);
        this.setFromPath(null);

        collectionsStore.reset();

        clearNuxtData(); // Remove personalized (or anonymous) cached data

        navigateTo(this.fromPath || '/');
      } else if (gotLoggedIn) {
        clearNuxtData(); // Remove personalized (or anonymous) cached data

        const user = new User(newUser.id);
        user.load().then(() => {
          this.setUser(user.toObject());

          this.updateUserCollections();
        });

        user.getPreferences().then(preferences => {
          this.setPreferences(preferences);
        });

        navigateTo(this.fromPath || '/');
      }

      // Restore the password expiry timer
      if (this.password && this.passwordExpiry) {
        const expiresIn = this.passwordExpiry - Date.now();
        this.setPassword(this.password, expiresIn);
      }
    }
  }
});
