set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.clean_app_collections()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_app public.apps%rowtype;
  item text;
begin
  -- Reset counter fields for all apps
  update public.apps
  set libraries = 0,
      wishlists = 0,
      tradelists = 0,
      blacklists = 0,
      bundles = 0,
      giveaways = 0,
      steam_packages = 0,
      steam_bundles = 0;
      
  -- Update counters based on collection_apps data
  -- Update library count
  update public.apps a
  set libraries = subquery.count
  from (
    select ca.app_id, count(*)::integer as count
    from public.collection_apps ca
    join public.collections c on ca.collection_id = c.id
    where c.type = 'library' and c.master = true
    group by ca.app_id
  ) as subquery
  where a.id = subquery.app_id;
  
  -- Update wishlist count
  update public.apps a
  set wishlists = subquery.count
  from (
    select ca.app_id, count(*)::integer as count
    from public.collection_apps ca
    join public.collections c on ca.collection_id = c.id
    where c.type = 'wishlist' and c.master = true
    group by ca.app_id
  ) as subquery
  where a.id = subquery.app_id;
  
  -- Update tradelist count
  update public.apps a
  set tradelists = subquery.count
  from (
    select ca.app_id, count(*)::integer as count
    from public.collection_apps ca
    join public.collections c on ca.collection_id = c.id
    where c.type = 'tradelist' and c.master = true
    group by ca.app_id
  ) as subquery
  where a.id = subquery.app_id;
  
  -- Update blacklist count
  update public.apps a
  set blacklists = subquery.count
  from (
    select ca.app_id, count(*)::integer as count
    from public.collection_apps ca
    join public.collections c on ca.collection_id = c.id
    where c.type = 'blacklist' and c.master = true
    group by ca.app_id
  ) as subquery
  where a.id = subquery.app_id;
  
  -- Update bundle count
  update public.apps a
  set bundles = subquery.count
  from (
    select ca.app_id, count(*)::integer as count
    from public.collection_apps ca
    join public.collections c on ca.collection_id = c.id
    where c.type = 'bundle' and c.user_id is null
    group by ca.app_id
  ) as subquery
  where a.id = subquery.app_id;
  
  -- Update giveaway count
  update public.apps a
  set giveaways = subquery.count
  from (
    select ca.app_id, count(*)::integer as count
    from public.collection_apps ca
    join public.collections c on ca.collection_id = c.id
    where c.type = 'giveaway' and c.user_id is null
    group by ca.app_id
  ) as subquery
  where a.id = subquery.app_id;
  
  -- Update steam package count
  update public.apps a
  set steam_packages = subquery.count
  from (
    select ca.app_id, count(*)::integer as count
    from public.collection_apps ca
    join public.collections c on ca.collection_id = c.id
    where c.type = 'steampackage' and c.user_id is null
    group by ca.app_id
  ) as subquery
  where a.id = subquery.app_id;
  
  -- Update steam bundle count
  update public.apps a
  set steam_bundles = subquery.count
  from (
    select ca.app_id, count(*)::integer as count
    from public.collection_apps ca
    join public.collections c on ca.collection_id = c.id
    where c.type = 'steambundle' and c.user_id is null
    group by ca.app_id
  ) as subquery
  where a.id = subquery.app_id;

  -- Remove all app-type collections
  delete from public.collection_apps
  where collection_id in (
    select id from public.collections
    where type = 'app'
    and user_id is null
  );

  -- Recreate app collections for each app
  for v_app in select * from public.apps loop
    -- Type collection
    if v_app.type is not null then
      perform public.add_collection_app('type-' || public.slugify(v_app.type::text), v_app.id, initcap(v_app.type::text) || ' (type)');
    end if;

    -- Developer collections
    if v_app.developers is not null then
      foreach item in array v_app.developers loop
        perform public.add_collection_app('developer-' || public.slugify(item), v_app.id, initcap(item) || ' (developer)');
      end loop;
    end if;

    -- Publisher collections
    if v_app.publishers is not null then
      foreach item in array v_app.publishers loop
        perform public.add_collection_app('publisher-' || public.slugify(item), v_app.id, initcap(item) || ' (publisher)');
      end loop;
    end if;

    -- Tag collections
    if v_app.tags is not null then
      foreach item in array v_app.tags loop
        perform public.add_collection_app('tag-' || public.slugify(item), v_app.id, initcap(item) || ' (tag)');
      end loop;
    end if;

    -- Language collections
    if v_app.languages is not null then
      foreach item in array v_app.languages loop
        perform public.add_collection_app('language-' || public.slugify(item), v_app.id, initcap(item) || ' (language)');
      end loop;
    end if;

    -- Platform collections
    if v_app.platforms is not null then
      foreach item in array v_app.platforms loop
        perform public.add_collection_app('platform-' || public.slugify(item), v_app.id, initcap(item) || ' (platform)');
      end loop;
    end if;

    -- Other collections
    if v_app.free is true or v_app.retail_price = 0 then
      perform public.add_collection_app('free', v_app.id, 'Free');
    end if;

    if v_app.plus_one is true then
      perform public.add_collection_app('plus-one', v_app.id, 'Plus One');
    end if;

    if v_app.exfgls is true then
      perform public.add_collection_app('exfgls', v_app.id, 'Excluded from Library Sharing');
    end if;

    if v_app.steamdeck in ('Playable', 'Verified') then
      perform public.add_collection_app('steamdeck', v_app.id, 'SteamDeck Compatible');
    end if;

    if v_app.cards > 0 then
      perform public.add_collection_app('with-cards', v_app.id, 'With Cards');
    end if;

    if v_app.achievements > 0 then
      perform public.add_collection_app('with-achievements', v_app.id, 'With Achievements');
    end if;

    if v_app.bundles > 0 then
      perform public.add_collection_app('bundled', v_app.id, 'Bundled');
    end if;

    if v_app.giveaways > 0 then
      perform public.add_collection_app('givenaway', v_app.id, 'Givenaway');
    end if;

    if v_app.removed_at is not null then
      perform public.add_collection_app('removed', v_app.id, 'Removed');
    end if;

    if v_app.removed_as is not null then
      perform public.add_collection_app('removed-' || public.slugify(v_app.removed_as), v_app.id, initcap(v_app.removed_as));
    end if;
  end loop;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.collection_apps_update_app_stats()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_collection_data record;
  increment integer;
  collection_type_map jsonb;
  column_name text;
begin
  -- Determine if we're incrementing (insert) or decrementing (delete)
  increment := case when tg_op = 'INSERT' then 1 else -1 end;
  
  -- Get the collection type and master status in a single query
  select type, master, user_id into v_collection_data
  from public.collections
  where id = case when tg_op = 'INSERT' then new.collection_id else old.collection_id end;
  
  -- Define the mapping of collection types to column names
  collection_type_map := '{
    "library": "libraries",
    "wishlist": "wishlists",
    "tradelist": "tradelists", 
    "blacklist": "blacklists",
    "bundle": "bundles",
    "giveaway": "giveaways",
    "steampackage": "steam_packages",
    "steambundle": "steam_bundles"
  }'::jsonb;
  
  -- Update statistics for: 
  -- 1. Master collections of specific types (library, wishlist, tradelist, blacklist)
  -- 2. System collections for bundle types (bundle, giveaway, steampackage, steambundle)
  if (v_collection_data.type in ('library', 'wishlist', 'tradelist', 'blacklist') and v_collection_data.master = true) or
     (v_collection_data.type in ('bundle', 'giveaway', 'steampackage', 'steambundle') and v_collection_data.user_id is null) then
    
    -- Get the column name from the mapping
    column_name := collection_type_map->>v_collection_data.type::text;
    
    -- Update the appropriate counter in the apps table
    execute format('
      update public.apps
      set %I = coalesce(%I, 0) + %L
      where id = %L
      and coalesce(%I, 0) + %L >= 0', -- Ensure count doesn't go below zero
      column_name, column_name, increment,
      case when tg_op = 'INSERT' then new.app_id else old.app_id end,
      column_name, increment
    );
  end if;
  
  return null; -- This is an AFTER trigger, so the return value is ignored
end;
$function$
;


