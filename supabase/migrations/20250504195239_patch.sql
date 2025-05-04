drop function if exists "public"."clean_app_collections"();

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.clean_app_collections(p_do_counts boolean DEFAULT true, p_do_collections boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET statement_timeout TO '3600s'
AS $function$
declare
  v_app public.apps%rowtype;
  item text;
begin
  perform pg_advisory_lock(4203596817983697560);

  -- Reset counter fields for all apps
  if p_do_counts then
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
    with app_counts as (
      select
        ca.app_id,
        count(*) filter (where c.type = 'library' and c.master)      as libraries,
        count(*) filter (where c.type = 'wishlist' and c.master)     as wishlists,
        count(*) filter (where c.type = 'tradelist' and c.master)    as tradelists,
        count(*) filter (where c.type = 'blacklist' and c.master)    as blacklists,
        count(*) filter (where c.type = 'bundle' and c.user_id is null)       as bundles,
        count(*) filter (where c.type = 'giveaway' and c.user_id is null)     as giveaways,
        count(*) filter (where c.type = 'steampackage' and c.user_id is null) as steam_packages,
        count(*) filter (where c.type = 'steambundle' and c.user_id is null)  as steam_bundles
      from public.collection_apps ca
      join public.collections c on ca.collection_id = c.id
      group by ca.app_id
    )
    update public.apps a
    set
      libraries      = ac.libraries,
      wishlists      = ac.wishlists,
      tradelists     = ac.tradelists,
      blacklists     = ac.blacklists,
      bundles        = ac.bundles,
      giveaways      = ac.giveaways,
      steam_packages = ac.steam_packages,
      steam_bundles  = ac.steam_bundles
    from app_counts ac
    where a.id = ac.app_id
      and (
        a.libraries      is distinct from ac.libraries or
        a.wishlists      is distinct from ac.wishlists or
        a.tradelists     is distinct from ac.tradelists or
        a.blacklists     is distinct from ac.blacklists or
        a.bundles        is distinct from ac.bundles or
        a.giveaways      is distinct from ac.giveaways or
        a.steam_packages is distinct from ac.steam_packages or
        a.steam_bundles  is distinct from ac.steam_bundles
      );
  end if;

  if p_do_collections then
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
  end if;
  
  perform pg_advisory_unlock(4203596817983697560);
end;
$function$
;


