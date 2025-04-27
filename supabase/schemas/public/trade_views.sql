-- Create trade_views table
create table trade_views (
  trade_id uuid references trades(id) on delete cascade,
  user_id uuid references users(id) on delete cascade,
  updated_at timestamptz default null,
  created_at timestamptz default now(),
  primary key (trade_id, user_id)
);

-- Add table comment
comment on table trade_views is 'Tracks the first and last trade view for each user';

-- Create trigger function to prevent user_id and trade_id changes
create or replace function trade_views_prevent_changes()
returns trigger
set search_path = ''
as $$
begin
  if new.trade_id != old.trade_id or new.user_id != old.user_id then
    raise exception 'Cannot change trade_id or user_id';
  end if;
  return new;
end;
$$ language plpgsql security invoker;

-- Create trigger
create trigger trade_views_prevent_changes_trigger
before update on trade_views
for each row
execute function trade_views_prevent_changes();

-- Add date management triggers
create trigger trade_views_update_dates
before update on trade_views
for each row
execute function update_dates();

create trigger trade_views_insert_dates
before insert on trade_views
for each row
execute function insert_dates();

-- Enable RLS
alter table trade_views enable row level security;

-- Allow read access for all users
create policy trade_views_select on trade_views
for select
to authenticated, anon
using (true);

-- Allow creation for own views only
create policy trade_views_insert on trade_views
for insert
to authenticated
with check ((select auth.uid()) = user_id);

-- Allow update for own views only
create policy trade_views_update on trade_views
for update
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

-- Disallow deletion for all users