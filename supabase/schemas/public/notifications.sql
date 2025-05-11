-- Create notification enum
create type notification as enum (
  'new_trade', 'accepted_trade', 'new_vault_entry', 'unread_messages', 'disputed_trade', 'resolved_trade'
);

-- Create notifications table
create table notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  type notification not null,
  link text default null check (
    -- Link must be a valid web URL or relative path
    link ~ '^(https?:\/\/[^\s/$.?#].[^\s]*)|(^\/[^\s]*)$'
  ),
  read boolean not null default false,
  created_at timestamptz default now()
);

-- Add table comment
comment on table notifications is 'User notifications for various events';

-- Enable realtime for this table
alter publication supabase_realtime add table notifications;

-- Add date management triggers
create trigger notifications_update_dates
before update on notifications
for each row
execute function update_dates();

create trigger notifications_insert_dates
before insert on notifications
for each row
execute function insert_dates();

-- Create trigger function to prevent changing any column except 'read'
create or replace function notifications_restrict_column_changes()
returns trigger
set search_path = ''
as $$
begin
  IF (old.user_id != new.user_id OR 
      old.type != new.type OR 
      old.link != new.link OR 
      old.created_at != new.created_at) THEN
    raise exception 'Only the "read" column can be updated in notifications';
  END IF;
  return new;
end;
$$ language plpgsql security invoker;

-- Create trigger
create trigger notifications_restrict_changes
before update on notifications
for each row
execute function notifications_restrict_column_changes();

-- Enable RLS
alter table notifications enable row level security;

-- Allow read access for own notifications only
create policy notifications_select on notifications
for select
to authenticated
using ((select auth.uid()) = user_id);

-- Disallow creation for all users

-- Allow update for own notifications only
create policy notifications_update on notifications
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

-- Disallow deletion for all users