alter table "public"."preferences" add column "track_vault_copies" boolean default false;

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.sync_vault_counts_on_pref_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user_id uuid := new.user_id;
  v_master_tradelist_id text;
  v_tag_id integer;
  v_app_id integer;
  v_count integer;
  v_enabled boolean := new.track_vault_copies;
begin
  -- Find master tradelist for user
  select id into v_master_tradelist_id from public.collections where user_id = v_user_id and master = true and type = 'tradelist';
  if v_master_tradelist_id is null then
    return null;
  end if;

  -- Find tag id for 'Count' tag of type 'tradelist'
  select id into v_tag_id from public.tags where title = 'Count' and type = 'tradelist';
  if v_tag_id is null then
    insert into public.tags (title, type) values ('Count', 'tradelist') returning id into v_tag_id;
  end if;

  if v_enabled and not old.track_vault_copies then
    -- Enabled: set all counts
    for v_app_id, v_count in select app_id, count(*) from public.vault_entries where user_id = v_user_id and trade_id is null group by app_id loop
      -- Remove any existing tag first
      delete from public.collection_tags where collection_id = v_master_tradelist_id and app_id = v_app_id and tag_id = v_tag_id;
      -- Insert tag with count
      insert into public.collection_tags (collection_id, app_id, tag_id, body) values (v_master_tradelist_id, v_app_id, v_tag_id, v_count::text);
    end loop;
  elsif not v_enabled and old.track_vault_copies then
    -- Disabled: remove all tags for apps that exist in vault_entries
    for v_app_id in select distinct app_id from public.vault_entries where user_id = v_user_id loop
      delete from public.collection_tags where collection_id = v_master_tradelist_id and app_id = v_app_id and tag_id = v_tag_id;
    end loop;
  end if;
  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.update_vault_count(p_user_id uuid, p_app_id integer, p_delta integer)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_track boolean;
  v_master_tradelist_id text;
  v_tag_id integer;
  v_existing_body text;
  v_new_count integer;
begin
  -- Check if user has track_vault_copies enabled
  select track_vault_copies into v_track from public.preferences where user_id = p_user_id;
  if not v_track then
    return;
  end if;

  -- Find master tradelist for user
  select id into v_master_tradelist_id from public.collections where user_id = p_user_id and master = true and type = 'tradelist';
  if v_master_tradelist_id is null then
    return;
  end if;

  -- Find tag id for 'Count' tag of type 'tradelist'
  select id into v_tag_id from public.tags where title = 'Count' and type = 'tradelist';
  if v_tag_id is null then
    -- Optionally, create the tag if not exists
    insert into public.tags (title, type) values ('Count', 'tradelist') returning id into v_tag_id;
  end if;

  -- Check if tag already exists for this app in master tradelist
  select body into v_existing_body from public.collection_tags where collection_id = v_master_tradelist_id and app_id = p_app_id and tag_id = v_tag_id;

  if v_existing_body is not null then
    -- Parse as integer, add delta
    v_new_count := coalesce((v_existing_body)::integer, 0) + p_delta;
    if v_new_count <= 0 then
      -- Remove tag if count is zero or less
      delete from public.collection_tags where collection_id = v_master_tradelist_id and app_id = p_app_id and tag_id = v_tag_id;
    else
      -- Update tag value
      update public.collection_tags set body = v_new_count::text where collection_id = v_master_tradelist_id and app_id = p_app_id and tag_id = v_tag_id;
    end if;
  else
    if p_delta > 0 then
      -- Insert new tag with value
      insert into public.collection_tags (collection_id, app_id, tag_id, body) values (v_master_tradelist_id, p_app_id, v_tag_id, p_delta::text);
    end if;
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.vault_entries_handle_vault_count()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  -- On insert: only if trade_id is null
  if tg_op = 'INSERT' and new.trade_id is null then
    perform public.update_vault_count(new.user_id, new.app_id, 1);
  end if;

  -- On update: if trade_id changed from null to not null (became traded)
  if tg_op = 'UPDATE' and old.trade_id is null and new.trade_id is not null then
    perform public.update_vault_count(new.user_id, new.app_id, -1);
  end if;

  -- On delete: only if trade_id is null
  if tg_op = 'DELETE' and old.trade_id is null then
    perform public.update_vault_count(old.user_id, old.app_id, -1);
  end if;

  return null;
end;
$function$
;

CREATE TRIGGER sync_vault_counts_on_pref_update_trigger AFTER UPDATE OF track_vault_copies ON public.preferences FOR EACH ROW WHEN ((old.track_vault_copies IS DISTINCT FROM new.track_vault_copies)) EXECUTE FUNCTION sync_vault_counts_on_pref_update();

CREATE TRIGGER vault_entries_handle_vault_count_delete AFTER DELETE ON public.vault_entries FOR EACH ROW EXECUTE FUNCTION vault_entries_handle_vault_count();

CREATE TRIGGER vault_entries_handle_vault_count_insert AFTER INSERT ON public.vault_entries FOR EACH ROW EXECUTE FUNCTION vault_entries_handle_vault_count();

CREATE TRIGGER vault_entries_handle_vault_count_update AFTER UPDATE ON public.vault_entries FOR EACH ROW EXECUTE FUNCTION vault_entries_handle_vault_count();


