-- Create vault entry type enum
create type vault_entry_type as enum (
  'key',
  'gift',
  'link',
  'curator'
);

-- Create vault_entries table
create table vault_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  app_id integer not null references apps(id) on delete cascade,
  trade_id uuid default null references trades(id) on delete cascade,
  type vault_entry_type not null,
  revealed_at timestamptz default null,
  updated_at timestamptz default null,
  created_at timestamptz default now()
);

-- Add table comment
comment on table vault_entries is 'Received and own vault entries';

-- Create trigger function to prevent id, user_id, app_id, trade_id changes
create or replace function vault_entries_prevent_changes()
returns trigger
set search_path = ''
as $$
begin
  if new.id != old.id or new.user_id != old.user_id or new.app_id != old.app_id or new.trade_id != old.trade_id then
    raise exception 'Cannot change id, user_id, app_id, or trade_id';
  end if;
  return new;
end;
$$ language plpgsql security invoker;

-- Create trigger function to handle notifications when vault entries are created
create or replace function vault_entries_handle_notifications()
returns trigger
set search_path = ''
as $$
begin
  -- Only process if trade_id is set
  if new.trade_id is not null then
    -- Only send notification if the user has enabled 'new_vault_entry' notifications
    if exists (
      select 1 from public.preferences
      where user_id = new.user_id
      and 'new_vault_entry' = ANY(enabled_notifications)
    ) then
      -- Create notification for the user who added the entry
      insert into public.notifications (user_id, type, link)
      values (new.user_id, 'new_vault_entry', '/vault?tab=received&appid=' || new.app_id);
    end if;
  end if;
  
  return new;
end;
$$ language plpgsql security definer;

-- Create triggers
create trigger vault_entries_ensure_app_exists
before insert on vault_entries
for each row
execute function ensure_app_exists();

create trigger vault_entries_prevent_changes_trigger
before update on vault_entries
for each row
execute function vault_entries_prevent_changes();

create trigger vault_entries_handle_notifications_trigger
after insert on vault_entries
for each row
execute function vault_entries_handle_notifications();

-- Add date management triggers
create trigger vault_entries_update_dates
before update on vault_entries
for each row
execute function update_dates();

create trigger vault_entries_insert_dates
before insert on vault_entries
for each row
execute function insert_dates();

-- Enable RLS
alter table vault_entries enable row level security;

-- Allow read access for own vault entries only
create policy vault_entries_select on vault_entries
for select
to authenticated
using ((select auth.uid()) = user_id);

-- Allow creation for own vault entries only
create policy vault_entries_insert on vault_entries
for insert
to authenticated
with check ((select auth.uid()) = user_id);

-- Allow update for my own vault entries only
create policy vault_entries_update on vault_entries
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

-- Allow deletion for own vault entries only
create policy vault_entries_delete on vault_entries
for delete
to authenticated
using ((select auth.uid()) = user_id);