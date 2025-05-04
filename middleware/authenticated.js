export default defineNuxtRouteMiddleware((to, from) => {
  const { setFromPath } = useAuthStore();
  const { isLoggedIn } = storeToRefs(useAuthStore());

  if (isLoggedIn.value || to.path.startsWith('/login') || to.path.startsWith('/logout') || from.path.startsWith('/login') || from.path.startsWith('/logout')) {
    return;
  }

  setFromPath(from.fullPath);

  return navigateTo('/login');
});
