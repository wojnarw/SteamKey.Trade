/**
 * Store for the snackbar component.
 *
 * @type {StoreDefinition<"snackbar", {
 *   visible: boolean,
 *   message: string,
 *   type: string
 * }>}
 */
export const useSnackbarStore = defineStore('snackbar', {
  state: () => ({
    visible: false,
    message: '',
    type: 'info',
    timeout: null
  }),

  actions: {
    /**
     * Set the snackbar message and type.
     *
     * @param {string} type - The type of the snackbar (e.g., 'info', 'success', 'error').
     * @param {string} message - The message to display in the snackbar.
     * @param {number|null} timeout - The duration in milliseconds before the snackbar disappears. If null, it will not disappear automatically.
     */
    set(type = 'info', message = '', timeout = null) {
      this.visible = false;
      this.message = message;
      this.type = type;
      this.visible = true;
      this.timeout = parseInt(timeout) || null;
    }
  }
});
