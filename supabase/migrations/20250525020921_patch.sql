set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.vault_entries_sync_tradelist_on_delete()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_master_tradelist_id text;
  v_count integer;
begin
  -- Check if user has any more available (tradeable) copies of this app
  select count(*) into v_count
  from public.vault_entries
  where user_id = old.user_id
    and app_id = old.app_id
    and trade_id is null;

  if v_count = 0 then
    -- Find the user's master tradelist
    select id into v_master_tradelist_id
    from public.collections
    where user_id = old.user_id and master = true and type = 'tradelist';

    if v_master_tradelist_id is not null then
      -- Remove from master tradelist if collection_apps entry is of type 'sync'
      delete from public.collection_apps
      where collection_id = v_master_tradelist_id
        and app_id = old.app_id
        and source = 'sync';
    end if;
  end if;

  return null;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.trades_handle_completed()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_new_vault_entry public.vault_entries%rowtype;
  v_vault_entry public.vault_entries%rowtype;
  v_user_id uuid;
  v_app_id integer;
  v_master_tradelist_id text;
  v_count integer;
  v_selected_apps integer[];
begin
  -- Skip if the trade is not completed or if vaultless, we are done
  if new.status != 'completed' or new.sender_vaultless = true then
    return new;
  end if;
  -- We assume that the trade is valid (checked in the status change trigger)

  -- Create received vault entries for each selected app
  for v_vault_entry in
    select * from public.vault_entries
    where id in (
      select vault_entry_id from public.trade_apps
      where trade_id = new.id
      and selected = true
    )
    and trade_id is null
  loop
    -- Create new vault entry
    insert into public.vault_entries (
      user_id,
      type,
      app_id,
      trade_id
    ) values (
      case 
        when v_vault_entry.user_id = new.sender_id then new.receiver_id
        else new.sender_id
      end,
      v_vault_entry.type,
      v_vault_entry.app_id,
      new.id
    ) returning * into v_new_vault_entry;
    
    -- Copy vault value from original entry to the new entry
    insert into public.vault_values (
      vault_entry_id,
      receiver_id,
      value
    )
    select 
      v_new_vault_entry.id as vault_entry_id,
      receiver_id,
      value
    from public.vault_values
    where vault_entry_id = v_vault_entry.id
    and receiver_id = v_new_vault_entry.user_id;

    -- Update the original entry with the completed trade ID (marking it as sent)
    update public.vault_entries
    set trade_id = new.id
    where id = v_vault_entry.id;
  end loop;

  -- Sync master tradelists for both users
  for v_user_id in select unnest(array[new.sender_id, new.receiver_id]) loop
    -- Get all apps this user traded away in this trade
    select array_agg(ta.app_id) into v_selected_apps
    from public.trade_apps ta
    join public.vault_entries ve on ta.vault_entry_id = ve.id
    where ta.trade_id = new.id
      and ta.selected = true
      and ve.user_id = v_user_id;

    if v_selected_apps is not null then
      -- Find the user's master tradelist
      select id into v_master_tradelist_id
      from public.collections
      where user_id = v_user_id and master = true and type = 'tradelist';

      if v_master_tradelist_id is not null then
        -- For each app, check if user has any more available in their vault
        foreach v_app_id in array v_selected_apps loop
          select count(*) into v_count
          from public.vault_entries
          where user_id = v_user_id
            and app_id = v_app_id
            and trade_id is null;

          if v_count = 0 then
            -- Remove from master tradelist if collection_apps entry is of type 'sync'
            delete from public.collection_apps
            where collection_id = v_master_tradelist_id
              and app_id = v_app_id
              and source = 'sync';
          end if;
        end loop;
      end if;
    end if;
  end loop;

  return new;
end;
$function$
;

CREATE TRIGGER vault_entries_sync_tradelist_on_delete_trigger AFTER DELETE ON public.vault_entries FOR EACH ROW EXECUTE FUNCTION vault_entries_sync_tradelist_on_delete();


-- Set source to 'sync' for master tradelist apps that have a vault entry for the user
update public.collection_apps ca
set source = 'sync'
from public.collections c
where ca.collection_id = c.id
  and c.master = true
  and c.type = 'tradelist'
  and exists (
    select 1
    from public.vault_entries ve
    where ve.user_id = c.user_id
      and ve.app_id = ca.app_id
  );