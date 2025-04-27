export default defineNuxtRouteMiddleware((to, from) => {
  const {
    isLoggedIn,
    setFromPath
  } = useAuthStore();

  if (isLoggedIn || ['/logout', '/login'].includes(to.path)) {
    return;
  }

  setFromPath(from.fullPath);

  return navigateTo('/login');
});
