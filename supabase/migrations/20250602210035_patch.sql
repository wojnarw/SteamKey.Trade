alter table "public"."trade_apps" drop constraint "trade_apps_vault_entry_id_fkey";

alter table "public"."trade_apps" add column "vault_entries" uuid[];

-- Migrate existing vault_entry_id to vault_entries
UPDATE trade_apps
SET vault_entries = ARRAY[vault_entry_id]
WHERE vault_entry_id IS NOT NULL;

alter table "public"."trade_apps" drop column "vault_entry_id";

alter table "public"."trade_apps" add column "total" integer not null default 1;


set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.trade_apps_validate_updates()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  -- Prevent updating certain fields
  if new.trade_id != old.trade_id or 
    new.user_id != old.user_id or 
    new.app_id != old.app_id or 
    new.collection_id != old.collection_id or 
    new.snapshot != old.snapshot then
    raise exception 'Cannot update trade_id, user_id, app_id, collection_id, or snapshot';
  end if;

  -- Validate mandatory updates
  if new.mandatory != old.mandatory and (
    not exists (
      select 1 from public.trades
      where id = new.trade_id
      and status = 'pending'
      and sender_id = (select auth.uid())
    )
  ) then
    raise exception 'Only sender can update mandatory on pending trades';
  end if;

  -- Validate selected updates
  if new.selected != old.selected and (
    not exists (
      select 1 from public.trades
      where id = new.trade_id
      and status = 'pending'
      and receiver_id = (select auth.uid())
    )
  ) then
      raise exception 'Only receiver can update selected on pending trades';
  end if;

  -- Validate vault_entries updates
  if new.vault_entries is distinct from old.vault_entries then
    -- Only allow setting vault entries that are not yet traded
    if exists (
      select 1 from public.vault_entries ve
      where ve.id = any(new.vault_entries)
        and ve.trade_id is not null
    ) or (
    -- Only allow update if the trade is not completed
      exists (
        select 1 from public.trades
        where id = new.trade_id
        and status = 'completed'
      ) or
      new.user_id != (select auth.uid())
    ) then
      raise exception 'Invalid vault_entries update';
    end if;
  end if;

  return new;
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
  v_vault_entry_id uuid;
begin
  -- Skip if the trade is not completed or if vaultless, we are done
  if new.status != 'completed' or new.sender_vaultless = true then
    return new;
  end if;
  -- We assume that the trade is valid (checked in the status change trigger)

  -- Create received vault entries for each selected app and each vault entry in the array
  for v_vault_entry_id in
    select unnest(ta.vault_entries) as vault_entry_id
    from public.trade_apps ta
    where ta.trade_id = new.id
      and ta.selected = true
      and ta.vault_entries is not null
  loop
    select * into v_vault_entry from public.vault_entries where id = v_vault_entry_id;
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
    join public.vault_entries ve on ve.id = any(ta.vault_entries)
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

CREATE OR REPLACE FUNCTION public.trades_validate_status_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- Status change validations
  if new.status != old.status then
    case new.status
      when 'aborted' then
        if old.status != 'accepted' then
          raise exception 'Can only abort accepted trades';
        end if;
      when 'accepted' then
        if old.status != 'pending' or (select auth.uid()) != new.receiver_id then
          raise exception 'Only receiver can accept pending trades';
        end if;
      when 'declined' then
        if old.status != 'pending' or (select auth.uid()) != new.receiver_id then
          raise exception 'Only receiver can decline pending trades';
        end if;
      when 'completed' then
        if old.status not in ('accepted', 'pending') or 
          -- Enforce both vaultless flags to be equal.
          new.sender_vaultless <> new.receiver_vaultless or
          -- If both are false then check that all selected trade apps have a vault entry assigned.
          (
            new.sender_vaultless = false and 
            exists (
              select 1 from public.trade_apps
              where trade_id = new.id
                and selected = true
                and (vault_entries is null or array_length(vault_entries, 1) = 0)
            )
          ) or
          -- If both are false then check that all assigned vault entries have a value for both sender and receiver.
          (
            new.sender_vaultless = false and 
            exists (
              select 1 from public.vault_entries ve
              join public.trade_apps ta on ve.id = any(ta.vault_entries)
              where ta.trade_id = new.id
                and ta.selected = true
                and ve.trade_id is null
                and (
                  not exists (
                    select 1 from public.vault_values vv
                    where vv.vault_entry_id = ve.id
                      and vv.receiver_id = new.sender_id
                  ) or 
                  not exists (
                    select 1 from public.vault_values vv
                    where vv.vault_entry_id = ve.id
                      and vv.receiver_id = new.receiver_id
                  )
                )
            )
          ) or
          -- Check that assigned vault entries for selected trade apps don't already have a trade assigned.
          (
            new.sender_vaultless = false and 
            exists (
              select 1 from public.vault_entries ve
              join public.trade_apps ta on ve.id = any(ta.vault_entries)
              where ta.trade_id = new.id
                and ta.selected = true
                and ve.trade_id is not null
            )
          ) or
          -- Check that for each selected trade_app, the number of distinct vault_entries matches total
          (
            new.sender_vaultless = false and
            exists (
              select 1 from public.trade_apps ta
              where ta.trade_id = new.id
                and ta.selected = true
                and ta.vault_entries is not null
                and array_length(array(select distinct unnest(ta.vault_entries)), 1) != ta.total
            )
          ) or
          -- Verify that the count of selected sender trade apps equals the expected sender_total.
          not exists (
            select 1 from public.trade_apps
            where trade_id = new.id
              and user_id = new.sender_id
              and selected = true
            group by trade_id
            having count(*) = new.sender_total
          ) or
          -- Verify that the count of selected receiver trade apps equals the expected receiver_total.
          not exists (
            select 1 from public.trade_apps
            where trade_id = new.id
              and user_id = new.receiver_id
              and selected = true
            group by trade_id
            having count(*) = new.receiver_total
          )
        then
            raise exception 'Invalid conditions for completing trade';
        end if;
    else
        raise exception 'Invalid status change';
    end case;
  end if;
  return new;
end;
$function$
;


