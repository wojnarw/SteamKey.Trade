drop function if exists "public"."get_master_collections_apps"(p_user_id uuid);

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.get_master_collections_apps(p_user_id uuid, p_source collection_apps_source DEFAULT NULL::collection_apps_source)
 RETURNS TABLE(tradelist json, wishlist json, library json, blacklist json)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
with recursive collection_hierarchy as (
  -- Find the user's master collections for the specified types
  select id, type
  from public.collections
  where user_id = p_user_id
    and master = true
    and type in ('tradelist', 'wishlist', 'library', 'blacklist')

  union all

  -- Recursively find all child collections through collection_relations
  select cr.collection_id, ch.type
  from public.collection_relations cr
  inner join collection_hierarchy ch on cr.parent_id = ch.id
)
select
  -- Aggregate app_ids for each type into a JSON array, filtered by source if provided
  (select json_agg(app_id) from public.collection_apps 
   where collection_id in (select id from collection_hierarchy where type = 'tradelist')
     and (p_source is null or source = p_source)) as tradelist,
  (select json_agg(app_id) from public.collection_apps 
   where collection_id in (select id from collection_hierarchy where type = 'wishlist')
     and (p_source is null or source = p_source)) as wishlist,
  (select json_agg(app_id) from public.collection_apps 
   where collection_id in (select id from collection_hierarchy where type = 'library')
     and (p_source is null or source = p_source)) as library,
  (select json_agg(app_id) from public.collection_apps 
   where collection_id in (select id from collection_hierarchy where type = 'blacklist')
     and (p_source is null or source = p_source)) as blacklist;
$function$
;


