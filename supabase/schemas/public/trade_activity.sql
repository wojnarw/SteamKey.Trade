-- Create trade_activity table
create table trade_activity (
  id uuid primary key default gen_random_uuid(),
  trade_id uuid not null references trades(id) on delete cascade,
  user_id uuid not null references users(id) on delete cascade,
  type trade_activity_type not null,
  updated_at timestamptz default null,
  created_at timestamptz default now()
);

-- Add table comment
comment on table trade_activity is 'Activity log for trades';

-- Enable realtime for this table
alter publication supabase_realtime add table trade_activity;

-- Add date management triggers
create trigger trade_activity_update_dates
before update on trade_activity
for each row
execute function update_dates();

create trigger trade_activity_insert_dates
before insert on trade_activity
for each row
execute function insert_dates();

-- Enable RLS
alter table trade_activity enable row level security;

-- Allow read access for all users
create policy trade_activity_select on trade_activity
for select
to authenticated, anon
using (true);

-- Disallow creation for all users
-- Disallow updates for all users
-- Disallow deletion for all users