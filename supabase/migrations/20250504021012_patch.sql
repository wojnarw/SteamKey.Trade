set check_function_bodies = off;

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
                and vault_entry_id is null
            )
          ) or
          -- If both are false then check that all assigned vault entries have a value for both sender and receiver.
          (
            new.sender_vaultless = false and 
            exists (
              select 1 from public.vault_entries ve
              join public.trade_apps ta on ta.vault_entry_id = ve.id
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
              join public.trade_apps ta on ta.vault_entry_id = ve.id
              where ta.trade_id = new.id
                and ta.selected = true
                and ve.trade_id is not null
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


