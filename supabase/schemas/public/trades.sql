-- Create trade status enum
create type trade_status as enum (
  'pending', 'accepted', 'declined', 'aborted', 'completed'
);

-- Create trade activity type enum
create type trade_activity_type as enum (
  'edited',
  'created',
  'accepted',
  'declined',
  'aborted',
  'completed',
  'disputed',
  'resolved',
  'countered'
);

-- Create trades table
create table trades (
  id uuid primary key default gen_random_uuid(),
  original_id uuid references trades(id) on delete cascade default null,
  status trade_status not null,
  sender_id uuid references users(id) on delete set null default null,
  sender_disputed boolean default false,
  sender_vaultless boolean default false,
  sender_total integer default 0 check (sender_total >= 0),
  receiver_id uuid references users(id) on delete set null default null,
  receiver_disputed boolean default false,
  receiver_vaultless boolean default false,
  receiver_total integer default 0 check (receiver_total >= 0),
  criteria jsonb default null,
  updated_at timestamptz default null,
  created_at timestamptz default now()
);

-- Add table comment
comment on table trades is 'Trade offers between users';

-- Create trigger function to validate trade creation
create or replace function trades_validate_creation()
returns trigger
set search_path = ''
as $$
begin
  -- Check if original trade exists and is valid for counter-offer
  if new.original_id is not null then
    if not exists (
      select 1 from public.trades
      where id = new.original_id
      and status = 'pending'
      and receiver_id = new.sender_id
    ) then
      raise exception 'Invalid original trade for counter-offer';
    end if;
  end if;
  return new;
end;
$$ language plpgsql security invoker;

-- Create trigger function to validate status changes
create or replace function trades_validate_status_change()
returns trigger
set search_path = ''
as $$
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
$$ language plpgsql security definer;

-- Create trigger function to validate dispute changes
create or replace function trades_validate_dispute_change()
returns trigger
set search_path = ''
as $$
begin
  if (new.sender_disputed != old.sender_disputed or new.receiver_disputed != old.receiver_disputed)
    and old.status != 'completed' then
    raise exception 'Can only dispute completed trades';
  end if;
  return new;
end;
$$ language plpgsql security invoker;

-- Create trigger function to prevent certain field changes
create or replace function trades_prevent_changes()
returns trigger
set search_path = ''
as $$
begin
  -- sender_id cannot change
  if new.sender_id != old.sender_id
  -- receiver_id cannot change
  or new.receiver_id != old.receiver_id
  -- original_id cannot change
  or new.original_id != old.original_id
  -- sender cannot change receiver_disputed or receiver_vaultless
  or ((select auth.uid()) = new.sender_id and (
    new.receiver_disputed != old.receiver_disputed or new.receiver_vaultless != old.receiver_vaultless
    ))
  -- receiver can only change status, receiver_disputed, or receiver_vaultless
  or ((select auth.uid()) = new.receiver_id and (
    new.sender_disputed != old.sender_disputed or
    new.sender_vaultless != old.sender_vaultless or
    new.sender_total != old.sender_total or
    new.receiver_total != old.receiver_total or
    new.criteria != old.criteria
  ))
    then
    raise exception 'Change not allowed';
  end if;
  return new;
end;
$$ language plpgsql security invoker;

-- Create trigger function to handle notifications for trades
create or replace function trades_handle_notifications()
returns trigger
set search_path = ''
as $$
begin
  -- For new trades, create a notification for the receiver if enabled
  if tg_op = 'INSERT' and new.receiver_id is not null then
    -- Only send notification if the user has enabled 'new_trade' notifications
    if exists (
      select 1 from public.preferences
      where user_id = new.receiver_id
      and 'new_trade' = ANY(enabled_notifications)
    ) then
      insert into public.notifications (user_id, type, link)
      values (new.receiver_id, 'new_trade', '/trade/' || new.id);
    end if;
  end if;

  -- For updates, create a notification for the sender if trade is accepted and if enabled
  if tg_op = 'UPDATE' and new.status = 'accepted' and new.sender_id is not null then
    -- Only send notification if the user has enabled 'accepted_trade' notifications
    if exists (
      select 1 from public.preferences
      where user_id = new.sender_id
      and 'accepted_trade' = ANY(enabled_notifications)
    ) then
      insert into public.notifications (user_id, type, link)
      values (new.sender_id, 'accepted_trade', '/trade/' || new.id);
    end if;
  end if;

  return new;
end;
$$ language plpgsql security definer;

-- Create trigger function to handle trade activity
create or replace function trades_handle_activity()
returns trigger
set search_path = ''
as $$
begin
  -- For new trades
  if tg_op = 'INSERT' then
    -- Record creation
    insert into public.trade_activity (trade_id, user_id, type)
    values (new.id, new.sender_id, 'created');
    
    -- Record counter if applicable
    if new.original_id is not null then
      insert into public.trade_activity (trade_id, user_id, type)
      values (new.id, new.sender_id, 'countered');
      
      -- abort original trade
      update trades set status = 'aborted' where id = new.original_id;
    end if;
  
  -- For updates
  elsif tg_op = 'UPDATE' then
    -- Status changes
    if new.status != old.status then
      insert into public.trade_activity (trade_id, user_id, type)
      values (new.id, (select auth.uid()), new.status::text::public.trade_activity_type);
    
    -- Dispute changes
    elsif (new.sender_disputed != old.sender_disputed or new.receiver_disputed != old.receiver_disputed) then
      if new.sender_disputed or new.receiver_disputed then
        insert into public.trade_activity (trade_id, user_id, type)
        values (new.id, (select auth.uid()), 'disputed');
      else
        insert into public.trade_activity (trade_id, user_id, type)
        values (new.id, (select auth.uid()), 'resolved');
      end if;
    
    -- Other changes
    else
      insert into public.trade_activity (trade_id, user_id, type)
      values (new.id, (select auth.uid()), 'edited');
    end if;
  end if;
  
  return new;
end;
$$ language plpgsql security definer;

-- Create trigger function to handle if a trade is completed
create or replace function trades_handle_completed()
returns trigger
set search_path = ''
as $$
declare
  v_new_vault_entry public.vault_entries%rowtype;
  v_vault_entry public.vault_entries%rowtype;
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
  return new;
end;
$$ language plpgsql security definer;

-- Create triggers
create trigger trades_validate_creation_trigger
before insert on trades
for each row
execute function trades_validate_creation();

create trigger trades_validate_status_change_trigger
before update of status on trades
for each row
execute function trades_validate_status_change();

create trigger trades_validate_dispute_change_trigger
before update of sender_disputed, receiver_disputed on trades
for each row
execute function trades_validate_dispute_change();

create trigger trades_prevent_changes_trigger
before update of sender_id, receiver_id on trades
for each row
execute function trades_prevent_changes();

create trigger trades_handle_activity_trigger
after insert or update on trades
for each row
execute function trades_handle_activity();

create trigger trades_handle_notifications_trigger
after insert or update on trades
for each row
execute function trades_handle_notifications();

create trigger trades_handle_completed_trigger
after update of status on trades
for each row
execute function trades_handle_completed();

-- Add date management triggers
create trigger trades_update_dates
before update on trades
for each row
execute function update_dates();

create trigger trades_insert_dates
before insert on trades
for each row
execute function insert_dates();

-- Enable RLS
alter table trades enable row level security;

-- Allow read access for all users
create policy trades_select on trades
for select
to authenticated, anon
using (true);

-- Allow creation with multiple conditions:
-- 1. User must be the sender
-- 2. Sender and receiver must be different
-- 3. Status must be pending
-- 4. Either receiver or criteria must be set, or both
create policy trades_insert on trades
for insert
to authenticated
with check (
  (select auth.uid()) = sender_id
  and sender_id != receiver_id
  and status = 'pending'
  and (receiver_id is not null or criteria is not null)
);

-- Allow update when user is sender or receiver
create policy trades_update on trades
for update
to authenticated
using (
  ((select auth.uid()) = sender_id or (select auth.uid()) = receiver_id)
)
with check (
  ((select auth.uid()) = sender_id or (select auth.uid()) = receiver_id)
);

-- Allow deletion with multiple conditions:
-- 1. User must be the sender
-- 2. Trade must be pending
create policy trades_delete on trades
for delete
to authenticated
using (
  (select auth.uid()) = sender_id
  and status = 'pending'
);