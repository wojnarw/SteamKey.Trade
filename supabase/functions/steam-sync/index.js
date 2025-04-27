import { serve } from '../_helpers/edge.js';
import { createAuthenticatedClient } from '../_helpers/supabase.js';
import { steamApiRequest } from '../_helpers/steamAPI.js';
import { User, Collection } from '../_entities/index.js';

/**
 * Generic function to sync a collection with Steam data
 * @param {import('@supabase/supabase-js').SupabaseClient} supabase - Supabase client
 * @param {User} user - User object
 * @param {string} collectionType - Type of collection to sync (wishlist or library)
 * @param {Function} fetchApps - Function to fetch apps from Steam API
 * @returns {Promise<Collection>} - Updated collection object
 */
const syncCollection = async (supabase, user, collectionType, fetchApps) => {
  // Get the appropriate collection based on type
  let collection;
  if (collectionType === Collection.enums.type.wishlist) {
    collection = await Collection.getMasterWishlist(supabase, user.id);
  } else if (collectionType === Collection.enums.type.library) {
    collection = await Collection.getMasterLibrary(supabase, user.id);
  }

  if (!collection) {
    throw new Error(`Master ${collectionType} collection not found`);
  }

  // Do not sync more than once per hour
  if (Date.now() - new Date(collection.updatedAt) < 1000 * 60 * 60) {
    const name = collectionType.charAt(0).toUpperCase() + collectionType.slice(1);
    const minutesRemaining = Math.ceil((1000 * 60 * 60 - (Date.now() - new Date(collection.updatedAt))) / (1000 * 60));
    throw new Error(`${name} was updated too recently. Please wait ${minutesRemaining} more minutes before syncing again.`);
  }

  const newApps = await fetchApps();
  const { error } = await supabase.rpc('sync_collection_apps', {
    p_collection_id: collection.id,
    p_apps: newApps.map(({ appId }) => Number(appId))
  });

  if (error) {
    throw new Error(`Failed to sync ${collectionType} collection: ${error.message}`);
  }

  collection.updatedAt = new Date();
  await collection.save();
  return collection;
};

/**
 * Fetch wishlist items from Steam API
 */
const fetchWishlist = async (steamId) => {
  const { items = [] } = await steamApiRequest('IWishlistService', 'GetWishlist', 'v1', {
    params: { steamid: steamId }
  });

  // TODO: Save date_added and priority as tag
  return items.map(({ appid, date_added }) => ({
    appId: Number(appid),
    createdAt: new Date(date_added * 1000)
  }));
};

/**
 * Fetch library items from Steam API
 */
const fetchLibrary = async (steamId) => {
  const { games = [] } = await steamApiRequest('IPlayerService', 'GetOwnedGames', 'v1', {
    params: {
      steamid: steamId,
      include_appinfo: false,
      include_played_free_games: true,
      include_free_sub: true,
      language: 'english',
      skip_unvetted_apps: false
    }
  });

  // TODO: Save playtime as tag
  return games.map(({ appid }) => ({ appId: Number(appid) }));
};

/**
 * Sync user's wishlist with Steam
 */
const syncMyWishlist = (supabase, user) => {
  return syncCollection(
    supabase,
    user,
    Collection.enums.type.wishlist,
    () => fetchWishlist(user.steamId)
  );
};

/**
 * Sync user's library with Steam
 */
const syncMyLibrary = (supabase, user) => {
  return syncCollection(
    supabase,
    user,
    Collection.enums.type.library,
    () => fetchLibrary(user.steamId)
  );
};

/**
 * Main handler for Steam sync endpoints
 */
const steamSync = async ({ userId, type }, req) => {
  const supabase = createAuthenticatedClient(req);

  if (!userId) {
    const { error, data } = await supabase.auth.getUser();
    if (error) {
      throw new Error('Either provide a user ID or authenticate the request');
    }
    userId = data.user.id;
  }

  const user = new User(supabase, userId);
  await user.load();

  if (!type) {
    const [wishlistCollection, libraryCollection] = await Promise.all([
      syncMyWishlist(supabase, user),
      syncMyLibrary(supabase, user)
    ]);
    return {
      success: true,
      wishlist: wishlistCollection.id,
      library: libraryCollection.id
    };
  } else if (type === Collection.enums.type.wishlist) {
    const collection = await syncMyWishlist(supabase, user);
    return { success: true, wishlist: collection.id };
  } else if (type === Collection.enums.type.library) {
    const collection = await syncMyLibrary(supabase, user);
    return { success: true, library: collection.id };
  } else {
    throw new Error(`Invalid collection type: ${type}`);
  }
};

serve(steamSync);